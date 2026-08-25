# typed: false
# frozen_string_literal: true

require 'opentelemetry'

module App
  module Observability
    # Wrappers prepended onto the app-area adapters, giving the otherwise
    # opaque AWS SDK client spans (a bare "dynamodb-local POST") a
    # semantically-named parent that says what the call is doing. The adapters
    # themselves stay unaware of OpenTelemetry, the same boundary the domain
    # wrappers keep; the only inline exception is the ElasticMQ poller, whose
    # cross-thread context propagation cannot be added from outside.
    module Adapters
      # Shared helper for the modules prepended onto adapter classes. The
      # tracer is resolved through the global provider, so it is a no-op unless
      # a driver has configured the SDK at boot.
      module Tracing
        private

        # @param source [String] the instrumentation scope name
        # @return [OpenTelemetry::Trace::Tracer]
        def adapter_tracer(source)
          OpenTelemetry.tracer_provider.tracer(source)
        end

        # @param operation [String] the Ruby method that owns the span
        # @param attributes [Hash] existing span attributes
        # @return [Hash]
        def operation_attributes(operation, attributes = {})
          attributes.merge('code.function' => "#{self.class.name}##{operation}")
        end

        # @param operation [String] the Ruby class method that owns the span
        # @param attributes [Hash] existing span attributes
        # @return [Hash]
        def class_operation_attributes(target, operation, attributes = {})
          attributes.merge('code.function' => "#{target.name}.#{operation}")
        end
      end
    end
  end
end
