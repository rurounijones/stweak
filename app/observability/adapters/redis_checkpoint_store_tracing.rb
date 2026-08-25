# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Adapters
      # Adds semantic parent spans around Redis checkpoint-store operations.
      # The Redis instrumentation remains underneath these spans as the
      # low-level client operation; checkpoint state stays out of telemetry.
      module RedisCheckpointStoreTracing
        include Tracing

        SOURCE = 'stweak-checkpoint-store'

        def get(owner_type:, owner_id:)
          in_owner_span('checkpoint.get', owner_type, owner_id) { super }
        end

        def put(owner_type:, owner_id:, checkpoint:)
          in_owner_span('checkpoint.put', owner_type, owner_id) { super }
        end

        def delete(owner_type:, owner_id:)
          in_owner_span('checkpoint.delete', owner_type, owner_id) { super }
        end

        private

        def in_owner_span(name, owner_type, owner_id, &)
          attributes = {
            'stweak.owner_type' => owner_type.name,
            'stweak.owner_id' => owner_id.to_s
          }
          adapter_tracer(SOURCE).in_span(name, attributes: operation_attributes(name.split('.').last, attributes), &)
        end
      end
    end
  end
end
