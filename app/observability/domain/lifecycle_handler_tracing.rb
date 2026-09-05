# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require 'stweak'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds a span around the disable and delete application services without
      # changing the domain. One module serves both handlers because their
      # shape is identical — each handles a command that names an account id —
      # and the command type picks the span name, so the traces read as the
      # account's lifecycle rather than as a generic handle.
      module LifecycleHandlerTracing
        include Tracing

        def handle(command)
          attributes = {
            'stweak.command' => command.class.name,
            'stweak.account_id' => command.account_id.to_s
          }
          domain_tracer.in_span(
            span_name_for(command), attributes: operation_attributes('handle', attributes)
          ) { super }
        end

        private

        # @param command [Stweak::Domain::Command]
        # @return [String]
        def span_name_for(command)
          case command
          when Stweak::Domain::Accounts::DisableAccount then 'domain.account.disable'
          when Stweak::Domain::Accounts::DeleteAccount then 'domain.account.delete'
          else
            raise ArgumentError, "unexpected lifecycle command #{command.class}"
          end
        end
      end
    end
  end
end
