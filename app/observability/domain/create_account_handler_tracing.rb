# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds a span around account-creation application service calls without
      # changing the domain implementation.
      module CreateAccountHandlerTracing
        include Tracing

        def handle(command)
          attributes = {
            'stweak.command' => command.class.name,
            'stweak.account_id' => command.account_id.to_s
          }
          domain_tracer.in_span(
            'domain.account.create', attributes: operation_attributes('handle', attributes)
          ) { super }
        end
      end
    end
  end
end
