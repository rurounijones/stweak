# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'tracing'

module App
  module Observability
    module Domain
      # Adds a span around Account aggregate commands without changing the domain.
      module AccountTracing
        include Tracing

        def create(username:, password_hash:, name:, email:, occurred_at:)
          attributes = {
            'stweak.aggregate' => self.class.name,
            'stweak.account_id' => id.to_s
          }
          domain_tracer.in_span(
            'domain.account.apply_create', attributes: operation_attributes('create', attributes)
          ) do
            super
          end
        end
      end
    end
  end
end
