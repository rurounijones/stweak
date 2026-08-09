# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'owner_registry'
require_relative 'projection'
require_relative '../ports/event_store'
require_relative '../ports/event_store_listener'
require_relative '../ports/event_subscription'
require_relative '../ports/projection_store'

module Stweak
  module Domain
    # Builds and maintains projections from the event store and subscription.
    class ProjectionSystem
      include Stweak::Ports::EventStoreListener

      extend T::Sig

      # @param event_store [Stweak::Ports::EventStore]
      # @param projection_store [Stweak::Ports::ProjectionStore]
      # @param subscription [Stweak::Ports::EventSubscription]
      sig do
        params(
          event_store: Stweak::Ports::EventStore,
          projection_store: Stweak::Ports::ProjectionStore,
          subscription: Stweak::Ports::EventSubscription
        ).void
      end
      def initialize(event_store:, projection_store:, subscription:)
        @event_store = event_store
        @projection_store = projection_store
        @cursors = T.let({}, T::Hash[Projection, T::Hash[String, Integer]])
        subscription.register(listener: self)
      end

      # Register a projection and optionally catch it up from the event store.
      # An application can perform an equivalent optimized catch-up first and
      # pass false to restore the cursors without replaying the streams again.
      #
      # @param projection [Projection]
      # @param catch_up [Boolean]
      sig { params(projection: Projection, catch_up: T::Boolean).void }
      def register(projection, catch_up: true)
        restore_from_store(projection)
        self.catch_up(projection) if catch_up
      end

      # Register a projection using an application-supplied stream reader and
      # event applier, preserving the normal cursor and transaction semantics.
      #
      # @param projection [Projection]
      # @param stream_reader [Proc] yields each stream's events
      # @param event_applier [Proc] applies one event to the projection
      sig do
        params(
          projection: Projection,
          stream_reader: T.untyped,
          event_applier: T.untyped
        ).void
      end
      def register_with(projection, stream_reader:, event_applier:)
        restore_from_store(projection)
        cursors = @cursors.fetch(projection).dup
        @projection_store.transaction do
          advanced = {}
          stream_reader.call do |_owner_type, _stream_id, events|
            advanced.merge!(apply_new_events(projection, events, cursors, event_applier))
          end
          persist(projection, advanced)
        end
        T.must(@cursors[projection]).replace(cursors)
      end

      # Rebuild a projection from the beginning of the log.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def rebuild(projection)
        cursors = {}
        @projection_store.transaction do
          projection.reset
          @projection_store.delete(projection_name: projection.name)
          catch_up_without_transaction(projection, cursors)
        end
        @cursors[projection] = cursors
      end

      # Handle an appended event batch for every registered projection.
      #
      # @param events [Array<Event>]
      sig { override.params(events: T::Array[Event]).void }
      def on_events_appended(events:)
        @cursors.each do |projection, cursors|
          process(projection, events, cursors)
        end
      end

      private

      # Restore a projection's stored cursors.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def restore_from_store(projection)
        @cursors[projection] = @projection_store.read(projection_name: projection.name) || {}
      end

      # Bring a projection current in one transaction.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def catch_up(projection)
        cursors = @cursors.fetch(projection).dup
        @projection_store.transaction do
          catch_up_without_transaction(projection, cursors)
        end
        T.must(@cursors[projection]).replace(cursors)
      end

      # Feed every stream to a projection. The caller owns the transaction.
      #
      # @param projection [Projection]
      # @param cursors [Hash{String => Integer}]
      sig { params(projection: Projection, cursors: T::Hash[String, Integer]).void }
      def catch_up_without_transaction(projection, cursors)
        advanced = {}
        @event_store.each_stream do |_owner_type, _stream_id, events|
          advanced.merge!(apply_new_events(projection, events, cursors))
        end
        persist(projection, advanced)
      end

      # Apply only events beyond the current stream cursor.
      #
      # @param projection [Projection]
      # @param events [Array<Event>]
      # @param cursors [Hash{String => Integer}]
      sig do
        params(projection: Projection, events: T::Array[Event], cursors: T::Hash[String, Integer]).void
      end
      def process(projection, events, cursors)
        pending_cursors = cursors.dup
        @projection_store.transaction do
          persist(projection, apply_new_events(projection, events, pending_cursors))
        end
        cursors.replace(pending_cursors)
      end

      sig do
        params(
          projection: Projection,
          events: T::Array[Event],
          cursors: T::Hash[String, Integer],
          event_applier: T.untyped
        ).returns(T::Hash[String, Integer])
      end
      def apply_new_events(projection, events, cursors, event_applier = nil)
        advanced = {}
        events.each do |event|
          key = stream_key_for(event)
          next if cursors.key?(key) && cursors.fetch(key) >= event.sequence

          event_applier ? event_applier.call(event) : projection.apply(event)
          cursors[key] = event.sequence
          advanced[key] = event.sequence
        end
        advanced
      end

      # Persist only cursors advanced by this batch.
      #
      # @param projection [Projection]
      # @param advanced [Hash{String => Integer}]
      sig { params(projection: Projection, advanced: T::Hash[String, Integer]).void }
      def persist(projection, advanced)
        return if advanced.empty?

        @projection_store.advance(projection_name: projection.name, cursors: advanced)
      end

      # @param event [Event]
      # @return [String]
      sig { params(event: Event).returns(String) }
      def stream_key_for(event)
        stream_key(OwnerRegistry.owner_type_for(event.class), event.stream_id)
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Id]
      # @return [String]
      sig do
        params(owner_type: T.class_of(Aggregate), stream_id: Id).returns(String)
      end
      def stream_key(owner_type, stream_id)
        "#{owner_type.name}##{stream_id}"
      end
    end
  end
end
