# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Adapters
      # Semantic spans for adapter operations whose underlying implementation
      # does not expose a separate client instrumentation span.
      module PortTracing
        include Tracing

        def digest(password:)
          adapter_tracer('stweak-password-hasher').in_span(
            'password.digest', attributes: operation_attributes('digest')
          ) { super }
        end

        def include?(username)
          adapter_tracer('stweak-usernames').in_span(
            'usernames.include', attributes: operation_attributes('include?')
          ) { super }
        end
      end

      # Semantic spans for relational projection-store port operations.
      module ProjectionStoreTracing
        include Tracing

        def transaction(&)
          adapter_tracer('stweak-projection-store').in_span(
            'projection.transaction', attributes: operation_attributes('transaction'), &
          )
        end

        def read(projection_name:)
          projection_span('projection.read', projection_name: projection_name) { super }
        end

        def write(projection_name:, cursors:)
          projection_span('projection.write', projection_name: projection_name, count: cursors.length) { super }
        end

        def advance(projection_name:, cursors:)
          projection_span('projection.advance', projection_name: projection_name, count: cursors.length) { super }
        end

        def delete(projection_name:)
          projection_span('projection.delete', projection_name: projection_name) { super }
        end

        def upsert(table:, attributes:)
          projection_span('projection.upsert', table: table, count: attributes.length) { super }
        end

        def delete_row(table:, id:)
          projection_span('projection.delete_row', table: table) { super }
        end

        def clear(table:)
          projection_span('projection.clear', table: table) { super }
        end

        def read_all(table:)
          projection_span('projection.read_all', table: table) { super }
        end

        private

        def projection_span(name, projection_name: nil, table: nil, count: nil, &)
          attributes = {}
          attributes['stweak.projection'] = projection_name if projection_name
          attributes['stweak.table'] = table.to_s if table
          attributes['stweak.count'] = count if count
          adapter_tracer('stweak-projection-store').in_span(
            name,
            attributes: operation_attributes(name.split('.').last, attributes), &
          )
        end
      end

      # Semantic spans for the encrypting checkpoint adapter.
      module EncryptingCheckpointStoreTracing
        include Tracing

        def get(owner_type:, owner_id:)
          owner_span('checkpoint.encrypt.get', 'get', owner_type, owner_id) { super }
        end

        def put(owner_type:, owner_id:, checkpoint:)
          owner_span('checkpoint.encrypt.put', 'put', owner_type, owner_id) { super }
        end

        def delete(owner_type:, owner_id:)
          owner_span('checkpoint.encrypt.delete', 'delete', owner_type, owner_id) { super }
        end

        private

        def owner_span(name, operation, owner_type, owner_id)
          attributes = { 'stweak.owner_type' => owner_type.name, 'stweak.owner_id' => owner_id.to_s }
          adapter_tracer('stweak-checkpoint-encryption').in_span(
            name, attributes: operation_attributes(operation, attributes)
          ) { yield }
        end
      end

      # Semantic spans for the encrypting event-store adapter.
      module EncryptingEventStoreTracing
        include Tracing

        def append(owner_type:, stream_id:, expected_version:, events:)
          attributes = {
            'stweak.aggregate' => owner_type.name,
            'stweak.stream_id' => stream_id.to_s,
            'stweak.event_count' => events.length
          }
          adapter_tracer('stweak-event-encryption').in_span(
            'eventstore.encrypt.append', attributes: operation_attributes('append', attributes)
          ) { super }
        end

        def read_stream(owner_type:, stream_id:, after: 0)
          attributes = {
            'stweak.aggregate' => owner_type.name,
            'stweak.stream_id' => stream_id.to_s,
            'stweak.after' => after
          }
          adapter_tracer('stweak-event-encryption').in_span(
            'eventstore.encrypt.read_stream', attributes: operation_attributes('read_stream', attributes)
          ) { super }
        end

        # Forward the caller's stream block through the encryption span.
        # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- explicit block keeps the delegated stream callback
        def each_stream(&block)
          adapter_tracer('stweak-event-encryption').in_span(
            'eventstore.encrypt.each_stream', attributes: operation_attributes('each_stream')
          ) do
            super(&block)
          end
        end
        # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding
      end

      module EncryptingProjectionStoreTracing
        include ProjectionStoreTracing
      end
    end
  end
end
