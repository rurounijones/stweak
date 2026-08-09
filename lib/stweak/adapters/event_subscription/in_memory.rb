# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../domain/event'
require_relative '../../ports/event_store_listener'
require_relative '../../ports/event_subscription'

module Stweak
  module Adapters
    # Event subscription adapters.
    module EventSubscription
      # An in-memory event subscription: listeners register here and are called
      # synchronously when the emitter publishes. It is the stand-in for a
      # production transport such as an SQS queue, which would deliver the same
      # events out of process; the contract is identical, only the delivery is
      # in-process. Nothing survives a restart, consistent with the project's
      # in-memory datastores.
      class InMemoryEventSubscription
        include Stweak::Ports::EventSubscription

        extend T::Sig

        sig { void }
        def initialize
          @listeners = T.let([], T::Array[Stweak::Ports::EventStoreListener])
        end

        # Register a listener to receive published events.
        #
        # @param listener [Stweak::Ports::EventStoreListener]
        sig { override.params(listener: Stweak::Ports::EventStoreListener).void }
        def register(listener:)
          @listeners << listener
        end

        # Deliver the events to every registered listener, in registration
        # order.
        #
        # @param events [Array<Stweak::Domain::Event>]
        sig { override.params(events: T::Array[Stweak::Domain::Event]).void }
        def publish(events:)
          @listeners.each do |listener|
            listener.on_events_appended(events: events)
          end
        end
      end
    end
  end
end
