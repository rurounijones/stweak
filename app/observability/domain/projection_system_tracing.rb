# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds spans around projection-system lifecycle and subscription callbacks.
      module ProjectionSystemTracing
        include Tracing

        def register(projection)
          attributes = { 'stweak.projection' => projection.name }
          domain_tracer.in_span(
            'domain.projection.register', attributes: operation_attributes('register', attributes)
          ) { super }
        end

        def rebuild(projection)
          attributes = { 'stweak.projection' => projection.name }
          domain_tracer.in_span(
            'domain.projection.rebuild', attributes: operation_attributes('rebuild', attributes)
          ) { super }
        end

        def register_with(projection, stream_reader:, event_applier:)
          attributes = { 'stweak.projection' => projection.name }
          domain_tracer.in_span(
            'domain.projection.register_with',
            attributes: operation_attributes('register_with', attributes)
          ) { super }
        end

        def on_events_appended(events:)
          attributes = { 'stweak.event_count' => events.length }
          domain_tracer.in_span(
            'domain.projection.on_events_appended',
            attributes: operation_attributes('on_events_appended', attributes)
          ) { super }
        end
      end
    end
  end
end
