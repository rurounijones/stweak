# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds spans around the Account aggregate's disable and delete transitions
      # without changing the domain, the sibling of AccountTracing covering the
      # lifecycle the newer events record.
      module LifecycleAccountTracing
        include Tracing

        # @param occurred_at [Time]
        def disable(occurred_at:)
          attributes = {
            'stweak.aggregate' => self.class.name,
            'stweak.account_id' => id.to_s
          }
          domain_tracer.in_span(
            'domain.account.apply_disable', attributes: operation_attributes('disable', attributes)
          ) { super }
        end

        # @param occurred_at [Time]
        def delete(occurred_at:)
          attributes = {
            'stweak.aggregate' => self.class.name,
            'stweak.account_id' => id.to_s
          }
          domain_tracer.in_span(
            'domain.account.apply_delete', attributes: operation_attributes('delete', attributes)
          ) { super }
        end
      end
    end
  end
end
