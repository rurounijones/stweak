# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Adapters
      # Adds a named span around each DynamoDB event-store operation, so the
      # AWS SDK's client spans nest beneath a parent that names the operation
      # rather than surfacing as bare POSTs. The store class is unchanged; the
      # spans carry only operation metadata, never the events' contents.
      module EventStoreTracing
        include Tracing

        SOURCE = 'stweak-event-store'

        def append(owner_type:, stream_id:, expected_version:, events:)
          attributes = {
            'stweak.aggregate' => owner_type.name,
            'stweak.stream_id' => stream_id.to_s,
            'stweak.event_count' => events.length
          }
          adapter_tracer(SOURCE).in_span(
            'eventstore.append', attributes: operation_attributes('append', attributes)
          ) { super }
        end

        def read_stream(owner_type:, stream_id:, after: 0)
          attributes = {
            'stweak.aggregate' => owner_type.name,
            'stweak.stream_id' => stream_id.to_s,
            'stweak.after' => after
          }
          adapter_tracer(SOURCE).in_span(
            'eventstore.read_stream', attributes: operation_attributes('read_stream', attributes)
          ) { super }
        end

        def each_stream(&)
          adapter_tracer(SOURCE).in_span(
            'eventstore.each_stream', attributes: operation_attributes('each_stream')
          ) { super }
        end

        private

        # Wraps the boot-time table creation, covering any CreateTable calls it
        # makes for tables that do not yet exist.
        def create_tables
          attributes = { 'stweak.table' => @streams_table }
          adapter_tracer(SOURCE).in_span(
            'eventstore.ensure_tables', attributes: operation_attributes('create_tables', attributes)
          ) { super }
        end
      end
    end
  end
end
