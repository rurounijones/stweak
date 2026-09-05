# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require 'stweak'
require_relative 'domain/account_tracing'
require_relative 'domain/aggregate_tracing'
require_relative 'domain/create_account_handler_tracing'
require_relative 'domain/lifecycle_account_tracing'
require_relative 'domain/lifecycle_handler_tracing'
require_relative 'domain/projection_system_tracing'

module App
  module Observability
    # Installs OpenTelemetry wrappers onto the domain without adding telemetry
    # dependencies to the domain gem or changing its classes.
    module Domain
      class << self
        # Install all domain wrappers once. Calling this repeatedly is harmless.
        #
        # @return [void]
        def install
          prepend_once(Stweak::Domain::Accounts::Account, AccountTracing)
          prepend_once(Stweak::Domain::Accounts::Account, LifecycleAccountTracing)
          prepend_once(Stweak::Domain::Accounts::CreateAccountHandler, CreateAccountHandlerTracing)
          prepend_once(Stweak::Domain::Accounts::DisableAccountHandler, LifecycleHandlerTracing)
          prepend_once(Stweak::Domain::Accounts::DeleteAccountHandler, LifecycleHandlerTracing)
          prepend_once(Stweak::Domain::ProjectionSystem, ProjectionSystemTracing)
          prepend_once(Stweak::Domain::Aggregate.singleton_class, AggregateTracing)
        end

        private

        # @param target [Module]
        # @param wrapper [Module]
        # @return [void]
        def prepend_once(target, wrapper)
          target.prepend(wrapper) unless target.ancestors.include?(wrapper)
        end
      end
    end
  end
end
