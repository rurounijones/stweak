# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds a span around aggregate replay, including the singleton method that
      # constructs an aggregate from its event stream.
      module AggregateTracing
        include Tracing

        def replay(id:, events:, checkpoint: nil)
          attributes = {
            'stweak.aggregate' => name,
            'stweak.aggregate_id' => id.to_s,
            'stweak.event_count' => events.length,
            'stweak.checkpointed' => !checkpoint.nil?
          }
          domain_tracer.in_span(
            'domain.aggregate.replay', attributes: class_operation_attributes(self, 'replay', attributes)
          ) do
            super
          end
        end
      end
    end
  end
end
