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
      # in-process. Each event is reconstructed from its serialized form before
      # delivery — the in-memory equivalent of the SQS transport serializing on
      # publish and deserializing on receipt — so an older-version event is
      # upcast on the way to a listener here too, and a listener never receives
      # the emitter's own object. Nothing survives a restart, consistent with
      # the project's in-memory datastores.
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
        # order. Each event is rebuilt from its serialized form first, upcasting
        # an older shape to the current one, so delivery matches the durable
        # transport's serialize-then-deserialize round-trip.
        #
        # @param events [Array<Stweak::Domain::Event>]
        sig { override.params(events: T::Array[Stweak::Domain::Event]).void }
        def publish(events:)
          delivered = events.map { |event| rebuild(event) }
          @listeners.each do |listener|
            listener.on_events_appended(events: delivered)
          end
        end

        private

        # Rebuild an event from its serialized form, upcasting an older shape to
        # the current one before from_h sees it — the read-path translation the
        # durable transport performs on deserialize. The event's own class is
        # the current class for its type, so no type-name registry is needed.
        #
        # @param event [Stweak::Domain::Event]
        # @return [Stweak::Domain::Event]
        sig { params(event: Stweak::Domain::Event).returns(Stweak::Domain::Event) }
        def rebuild(event)
          klass = event.class
          klass.from_h(klass.upcast(event.to_h))
        end
      end
    end
  end
end
