# typed: strict
# frozen_string_literal: true

require 'aws-sdk-sqs'
require 'json'
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
        # rubocop:disable-next ThreadSafety/NewThread -- the poller runs on its own thread by design
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
        @sqs.send_message(
          queue_url: @queue_url,
          message_body: JSON.generate('events' => events.map { |event| serialize(event) })
        )
      end

      # Stop the poller; the subscription will no longer deliver. Call this
      # when shutting down, so the polling thread is not left running.
      sig { void }
      def stop
        @poller.kill
        @poller.join
      end

      private

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
      sig { void }
      def poll_once
        messages = @sqs.receive_message(queue_url: @queue_url, max_number_of_messages: 10).messages
        messages.each do |message|
          dispatch(message.body)
          @sqs.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
        rescue StandardError
          # Leave the message in the queue; it will be retried next poll.
        end
      end

      # Deliver one message's batch to every registered listener.
      #
      # @param body [String]
      sig { params(body: String).void }
      def dispatch(body)
        data = JSON.parse(body)
        events = data.fetch('events').map { |serialized| deserialize(serialized) }
        @listeners.each do |listener|
          listener.on_events_appended(events: events)
        end
      end
    end
  end
end
