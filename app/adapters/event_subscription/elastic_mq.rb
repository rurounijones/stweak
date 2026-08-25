# typed: strict
# frozen_string_literal: true

require 'aws-sdk-sqs'
require 'json'
require 'opentelemetry'
require 'sorbet-runtime'
require 'stweak'
require 'uri'
require_relative '../event_serialization'

module App
  module Adapters
    # An event subscription backed by ElasticMQ's SQS-compatible interface: the
    # real, out-of-process implementation of Stweak::Ports::EventSubscription,
    # living alongside the domain gem's in-memory one to prove the port is
    # interchangeable. Publish sends the batch to a queue; a background poller
    # reads the queue and delivers each batch to the registered listeners,
    # preserving the port's at-least-once contract — a message may be delivered
    # more than once. The poller runs for the lifetime of the subscription,
    # which in the data generator is the whole process.
    #
    # Because publish and delivery are separated by the queue and by the poller
    # thread — and a span's context is thread-local — a consumer's spans would
    # otherwise start their own disconnected traces. To link them, publish
    # injects the current trace context into the message and delivery reopens
    # it as a consumer span, so the projector's work nests under the command
    # that produced the event. With no SDK configured the tracer and propagator
    # are no-ops, so this costs nothing when tracing is off.
    class ElasticMqSubscription
      include Stweak::Ports::EventSubscription
      include App::Adapters::EventSerialization

      extend T::Sig

      # The queue events are published to and polled from.
      #
      # @return [String]
      sig { returns(String) }
      attr_reader :queue_url

      # @param sqs [Aws::SQS::Client] the client; the caller points it at
      #   ElasticMQ or a real endpoint
      # @param queue_name [String] the queue to publish to and poll; created if
      #   it does not exist
      # @param poll_interval [Float] how long to wait between polls, in seconds
      sig do
        params(
          sqs: Aws::SQS::Client,
          queue_name: String,
          poll_interval: Float
        ).void
      end
      def initialize(sqs:, queue_name:, poll_interval: 0.05)
        @sqs = sqs
        @queue_url = ensure_queue(queue_name)
        @listeners = T.let([], T::Array[Stweak::Ports::EventStoreListener])
        @poll_interval = poll_interval
        # Counters for draining: messages published, and messages fully
        # processed (delivered to the listeners and deleted). A short-lived
        # caller drains by waiting for the second to catch the first. The
        # queue's own ApproximateNumber* attributes are not exact enough to
        # drain on — a just-published message can read as absent — so the
        # subscription counts for itself. Written from two threads (published
        # by the publisher, processed by the poller) and read by the drainer;
        # this leans on the same MRI thread-visibility the listener list does.
        @published = T.let(0, Integer)
        @processed = T.let(0, Integer)
        # A no-op tracer unless a driver has configured the SDK at boot, so the
        # consumer span below costs nothing with tracing off.
        tracer = OpenTelemetry.tracer_provider.tracer('stweak-event-subscription')
        @tracer = T.let(tracer, OpenTelemetry::Trace::Tracer)
        @poller = T.let(Thread.new { poll_loop }, Thread)
      end

      # @param listener [Stweak::Ports::EventStoreListener]
      sig { override.params(listener: Stweak::Ports::EventStoreListener).void }
      def register(listener:)
        @listeners << listener
      end

      # @param events [Array<Stweak::Domain::Event>]
      sig { override.params(events: T::Array[Stweak::Domain::Event]).void }
      def publish(events:)
        # Carry the current trace context alongside the events, so the consumer
        # can reopen it and its work joins this producer's trace. Empty when
        # tracing is off, and ignored on read by any consumer that does not
        # look for it.
        carrier = {}
        OpenTelemetry.propagation.inject(carrier)
        @sqs.send_message(
          queue_url: @queue_url,
          message_body: JSON.generate(
            'events' => events.map { |event| serialize(event) }, 'trace' => carrier
          )
        )
        @published += 1
      end

      # Stop the poller; the subscription will no longer deliver. Call this
      # when shutting down, so the polling thread is not left running.
      sig { void }
      def stop
        @poller.kill
        @poller.join
      end

      # Block until every published message has been delivered and removed from
      # the queue, then stop the poller. A short-lived caller — the data
      # generator — uses this to let the read side catch up before it exits,
      # rather than leaving messages unconsumed and projections behind. Bounded
      # by timeout so a stuck consumer cannot hang the caller forever.
      #
      # @param timeout [Float] the longest to wait, in seconds
      sig { params(timeout: Float).void }
      def drain(timeout: 30.0)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        sleep @poll_interval until drained? || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        stop
      end

      private

      # Whether every published message has been fully processed — delivered to
      # the listeners and deleted. The poller increments the processed count
      # only after a delete, which happens only after delivery, so the counts
      # meeting means no published message is still outstanding.
      #
      # @return [Boolean]
      sig { returns(T::Boolean) }
      def drained?
        @processed >= @published
      end

      # The queue's URL, creating the queue if it does not exist. ElasticMQ
      # returns a URL on its own host (localhost), which is not reachable from
      # a sibling container; the URL is rebuilt on the client's endpoint.
      #
      # @param queue_name [String]
      # @return [String]
      sig { params(queue_name: String).returns(String) }
      def ensure_queue(queue_name)
        url = @sqs.create_queue(queue_name: queue_name).queue_url
        endpoint = URI.parse(T.must(@sqs.config.endpoint))
        uri = URI.parse(url)
        uri.scheme = endpoint.scheme
        uri.host = endpoint.host
        uri.port = endpoint.port
        uri.to_s
      end

      # The poller loop: receive a batch of messages, dispatch each, then wait.
      # Errors are swallowed and the loop continues, so a transient failure
      # does not kill the subscription.
      sig { void }
      def poll_loop
        loop do
          poll_once
          sleep @poll_interval
        rescue StandardError
          sleep @poll_interval
        end
      end

      # Receive and dispatch a batch of messages, deleting each once delivered.
      # A message that fails to dispatch is left for retry, and does not stop
      # the rest of the batch from being delivered.
      #
      # The poll runs on the poller thread, outside any command's context, so
      # its SQS calls would otherwise surface as bare, unhelpfully-named POST
      # spans. Wrapping the poll in a named span gives them an obvious parent;
      # each delivered batch still reopens its producer's trace inside dispatch.
      sig { void }
      def poll_once
        @tracer.in_span(
          'event_subscription.poll',
          attributes: { 'code.function' => 'App::Adapters::ElasticMqSubscription#poll_once' }
        ) do
          messages = @sqs.receive_message(queue_url: @queue_url, max_number_of_messages: 10).messages
          messages.each do |message|
            dispatch(message.body)
            @sqs.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
            @processed += 1
          rescue StandardError
            # Leave the message in the queue; it will be retried next poll.
          end
        end
      end

      # Deliver one message's batch to every registered listener, within a
      # consumer span reopened from the trace context the producer carried in
      # the message. The span becomes the parent of whatever the listeners do,
      # so the projector's work joins the trace of the command that produced
      # the event rather than starting its own. A message without a trace
      # context — an old one, or one from a producer that did not inject —
      # yields an empty carrier, so the span is simply a root.
      #
      # @param body [String]
      sig { params(body: String).void }
      def dispatch(body)
        data = JSON.parse(body)
        events = data.fetch('events').map { |serialized| deserialize(serialized) }
        parent = OpenTelemetry.propagation.extract(data.fetch('trace', {}))
        OpenTelemetry::Context.with_current(parent) do
          @tracer.in_span(
            'event_subscription.deliver',
            attributes: { 'code.function' => 'App::Adapters::ElasticMqSubscription#dispatch' },
            kind: :consumer
          ) do
            @listeners.each do |listener|
              listener.on_events_appended(events: events)
            end
          end
        end
      end
    end
  end
end
