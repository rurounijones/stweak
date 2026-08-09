# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/event'
require_relative 'event_store_listener'

module Stweak
  module Ports
    # The channel between the event store (the emitter) and its consumers (the
    # listeners): the decoupling point of the read side. The emitter publishes
    # appended events and does not know the listeners; a listener registers and
    # does not know the emitter. In memory the delivery is a synchronous
    # callback in the publishing process; in production the same contract would
    # be met by a queue such as SQS, with the publish side sending to the queue
    # and a consumer delivering from it. Either way the emitter and consumer
    # meet only here.
    module EventSubscription
      extend T::Sig
      extend T::Helpers

      interface!

      # Register a listener to receive published events. A listener may
      # register at any time; events published before it registered must be
      # caught up by other means, such as reading the log.
      #
      # @param listener [EventStoreListener]
      sig { abstract.params(listener: EventStoreListener).void }
      def register(listener:); end

      # Deliver the appended events to every registered listener, in order.
      # Delivery is at-least-once: a listener may receive a batch more than
      # once (a retry, or a queue delivering a record twice), and must tolerate
      # that — a projection does, by tracking, per stream, how far it has
      # consumed.
      #
      # @param events [Array<Stweak::Domain::Event>] the appended events, in
      #   append order
      sig { abstract.params(events: T::Array[Stweak::Domain::Event]).void }
      def publish(events:); end
    end
  end
end
