# typed: false
# frozen_string_literal: true

require 'opentelemetry'

module App
  module Observability
    module Domain
      # Shared helpers for the modules prepended onto domain classes. The domain
      # itself remains unaware of OpenTelemetry; these wrappers are installed by
      # a driver's composition root only when tracing is enabled.
      module Tracing
        private

        # @return [OpenTelemetry::Trace::Tracer]
        def domain_tracer
          OpenTelemetry.tracer_provider.tracer('stweak-domain')
        end

        # @param method_name [String] the instance method that owns the span
        # @param attributes [Hash] existing span attributes
        # @return [Hash]
        def operation_attributes(method_name, attributes = {})
          attributes.merge('code.function' => "#{self.class.name}##{method_name}")
        end

        # @param target [Module] the class whose method owns the span
        # @param method_name [String] the class method that owns the span
        # @param attributes [Hash] existing span attributes
        # @return [Hash]
        def class_operation_attributes(target, method_name, attributes = {})
          attributes.merge('code.function' => "#{target.name}.#{method_name}")
        end
      end
    end
  end
end
