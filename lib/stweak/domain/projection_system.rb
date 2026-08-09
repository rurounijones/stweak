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
    # The machinery that builds and maintains projections: the read side's
    # application service, mirroring CreateAccountHandler on the write side. It
    # registers on the event subscription, so it is fed every append the event
    # store publishes, and it feeds each projection it is tracking, keeping its
    # per-stream cursors durable in the projection store. A projection resumes
    # from its stored cursors instead of replaying the whole log; re-delivered
    # events are skipped by the per-stream cursor, so the system is safe under
    # the subscription's at-least-once delivery. It can also rebuild a
    # projection from the beginning of the log when its shape changes or it is
    # replaced.
    #
    # Each cursor is a stream mapped to the highest sequence consumed from it,
    # keyed by the stream's owner and id. Events on different streams have no
    # order relative to each other; a projection only ever needs the events of
    # each stream in that stream's own order.
    class ProjectionSystem
      include Stweak::Ports::EventStoreListener

      extend T::Sig

      # @param event_store [Stweak::Ports::EventStore] the streams, read when
      #   catching a projection up or rebuilding one
      # @param projection_store [Stweak::Ports::ProjectionStore] where each
      #   projection's cursors are kept
      # @param subscription [Stweak::Ports::EventSubscription] the channel
      #   that delivers appended events; the system registers as a listener
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

      # Start tracking a projection: restore its cursors from the store, bring
      # it current with every stream from that point (the beginning, for a
      # projection never stored), and feed it every subsequent append.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def register(projection)
        restore_from_store(projection)
        catch_up(projection)
      end

      # Rebuild a projection from the beginning of the log: reset it, discard
      # its stored cursors, replay every stream, and keep it fed by subsequent
      # appends. For when a projection's shape changes or it needs replacing.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def rebuild(projection)
        projection.reset
        @projection_store.delete(projection_name: projection.name)
        @cursors[projection] = {}
        catch_up(projection)
      end

      # The subscription's callback: react to an append by feeding each
      # tracked projection the events it has not yet consumed, then persisting
      # its cursors. Events the projection has already seen — a re-delivered
      # batch — are skipped by cursor, so the callback is safe under
      # at-least-once delivery.
      #
      # @param events [Array<Event>] the appended events, in append order
      sig { override.params(events: T::Array[Event]).void }
      def on_events_appended(events:)
        @cursors.each do |projection, cursors|
          advanced = apply_new_events(projection, events, cursors)
          persist(projection, cursors, advanced)
        end
      end

      private

      # Restore a projection's cursors from the store, or leave it empty with
      # no cursors if it has never been stored. A projection's materialized
      # state needs no restore: it is the rows of its table, which survive in
      # the store independently of the cursors.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def restore_from_store(projection)
        @cursors[projection] = @projection_store.read(projection_name: projection.name) || {}
      end

      # Feed a projection every event appended since it last caught up: fold
      # each stream's events that are newer than its cursor, from the cursor
      # to the end of the stream, and record how far it has consumed. The
      # cursors are always present: register and rebuild set them before
      # calling this, so fetching without a default fails loudly if a
      # projection was never tracked.
      #
      # @param projection [Projection]
      sig { params(projection: Projection).void }
      def catch_up(projection)
        cursors = @cursors.fetch(projection)
        advanced = []
        @event_store.each_stream do |_owner_type, _stream_id, events|
          advanced.concat(apply_new_events(projection, events, cursors))
        end
        persist(projection, cursors, advanced)
      end

      # Fold in only the events the projection has not yet consumed, advancing
      # the given cursors as it goes. A re-delivered or already-consumed event
      # is skipped by its stream's cursor. Returns the stream keys whose cursors
      # advanced, so only those are persisted rather than the whole map.
      #
      # @param projection [Projection]
      # @param events [Array<Event>]
      # @param cursors [Hash{String => Integer}]
      # @return [Array<String>] the stream keys advanced by this batch
      sig do
        params(projection: Projection, events: T::Array[Event], cursors: T::Hash[String, Integer])
          .returns(T::Array[String])
      end
      def apply_new_events(projection, events, cursors)
        events.each_with_object([]) do |event, advanced|
          key = stream_key_for(event)
          next if cursors.key?(key) && cursors.fetch(key) >= event.sequence

          projection.apply(event)
          cursors[key] = event.sequence
          advanced << key
        end
      end

      # The cursor key for an event's stream, qualified by owner so that two
      # aggregates of different kinds sharing an id never share a cursor.
      #
      # @param event [Event]
      # @return [String]
      sig { params(event: Event).returns(String) }
      def stream_key_for(event)
        stream_key(OwnerRegistry.owner_type_for(event.class), event.stream_id)
      end

      # The cursor key for a stream: its owner class and id.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Id]
      # @return [String]
      sig do
        params(owner_type: T.class_of(Aggregate), stream_id: Id)
          .returns(String)
      end
      def stream_key(owner_type, stream_id)
        "#{owner_type.name}##{stream_id}"
      end

      # Persist only the cursors this batch advanced, not the whole accumulated
      # map: the store merges them into what it already holds, so re-writing
      # every stream after each batch — quadratic work over a long run — is
      # avoided. A batch that advanced nothing (a re-delivery, or an empty log)
      # writes nothing at all. The delta is a fresh hash, so the store never
      # shares the working map, and a later in-place advance is not observed as
      # if it had been persisted.
      #
      # @param projection [Projection]
      # @param cursors [Hash{String => Integer}]
      # @param advanced [Array<String>] the stream keys advanced by this batch
      sig do
        params(projection: Projection, cursors: T::Hash[String, Integer], advanced: T::Array[String]).void
      end
      def persist(projection, cursors, advanced)
        return if advanced.empty?

        delta = advanced.to_h { |key| [key, cursors.fetch(key)] }
        @projection_store.write(projection_name: projection.name, cursors: delta)
      end
    end
  end
end
