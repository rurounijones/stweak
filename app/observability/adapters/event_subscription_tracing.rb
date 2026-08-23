# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Adapters
      # Adds a named span around the caller-thread ElasticMQ operations, so the
      # SendMessage and CreateQueue client spans nest beneath a parent that
      # names the operation. The poller thread's receive/delete and delivery
      # spans are instrumented inside the adapter itself, because their
      # cross-thread trace-context propagation cannot be added from outside.
      module EventSubscriptionTracing
        include Tracing

        SOURCE = 'stweak-event-subscription'

        def publish(events:)
          attributes = { 'stweak.event_count' => events.length }
          adapter_tracer(SOURCE).in_span(
            'subscription.publish', attributes: operation_attributes('publish', attributes)
          ) { super }
        end

        private

        # Wraps the boot-time queue creation. Private, matching the method it
        # prepends, so the subscription's surface is unchanged.
        def ensure_queue(queue_name)
          attributes = { 'stweak.queue' => queue_name }
          adapter_tracer(SOURCE).in_span(
            'subscription.ensure_queue', attributes: operation_attributes('ensure_queue', attributes)
          ) { super }
        end
      end
    end
  end
end
