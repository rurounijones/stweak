# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'checkpoint'
require_relative 'event'
require_relative 'id'

module Stweak
  module Domain
    # The base class for aggregates: the unit a command is addressed to and
    # that guards the rules. An aggregate is rebuilt by replaying its own event
    # stream, decides whether a command is allowed, and emits the events that
    # follow from allowing it. Rules can be enforced within one aggregate; rules
    # spanning several aggregates are handled elsewhere.
    #
    # Replay can start from a checkpoint: the aggregate restores its state from
    # the checkpoint and applies only the events after it, so a long stream
    # does not have to be replayed in full. Checkpointing is an implementation
    # detail of the aggregate — whether a replay used a checkpoint or not is
    # invisible to the caller, and the decision of when a checkpoint is due
    # lives here, in the base.
    class Aggregate
      extend T::Sig
      extend T::Helpers

      abstract!

      # How often the aggregate takes a checkpoint: once its stream has reached
      # this many events, the state is saved so a later replay can start from
      # it rather than from the beginning.
      CHECKPOINT_INTERVAL = 100

      sig { returns(Id) }
      attr_reader :id

      # The version of the stream this aggregate was rebuilt to. An append of
      # the aggregate's uncommitted events must expect this version, so the
      # event store can refuse the write if anything has been appended in the
      # meantime.
      sig { returns(Integer) }
      attr_reader :expected_version

      # The events this aggregate has produced but not yet appended.
      sig { returns(T::Array[Event]) }
      attr_reader :uncommitted_events

      # @param id [Id] the aggregate's identity, also its stream id
      sig { params(id: Id).void }
      def initialize(id:)
        @id = id
        @expected_version = T.let(0, Integer)
        # Declared untyped rather than `T::Array[Event]`: a `T.let` type
        # annotation has no runtime behaviour for mutation testing to pin (an
        # empty array vacuously satisfies either type). The reader below
        # exposes the precise type.
        @uncommitted_events = T.let([], T.untyped)
      end

      # Rebuild an aggregate from its stream. When a checkpoint is given, the
      # aggregate restores its state from it and applies only the events after
      # the checkpoint's version; any event at or before that version is
      # skipped, so passing the full stream works as well as passing only the
      # tail. The aggregate's expected version tracks the last event applied.
      #
      # @param id [Id]
      # @param events [Array<Event>] the events in the stream, in order
      # @param checkpoint [Checkpoint, nil] a checkpoint to restore from, or
      #   nil to replay from the beginning of the stream
      # @return [Aggregate] an instance of the class replay is called on
      sig do
        params(id: Id, events: T::Array[Event], checkpoint: T.nilable(Checkpoint))
          .returns(T.attached_class)
      end
      def self.replay(id:, events:, checkpoint: nil)
        aggregate = new(id: id)
        restore_from(checkpoint, aggregate) if checkpoint
        events.each do |event|
          next if event.sequence <= aggregate.expected_version

          aggregate.apply(event)
          aggregate.advance_to(event.sequence)
        end
        aggregate
      end

      # Restore an aggregate's state from a checkpoint and advance it to the
      # checkpoint's version, so that replay applies only the events after it.
      #
      # @param checkpoint [Checkpoint]
      # @param aggregate [Aggregate]
      sig { params(checkpoint: Checkpoint, aggregate: Aggregate).void }
      def self.restore_from(checkpoint, aggregate)
        aggregate.restore(checkpoint.state)
        aggregate.advance_to(checkpoint.version)
      end
      private_class_method :restore_from

      # Fold an event into the aggregate's state. Called for every event on
      # replay and for every event the aggregate records itself. Subclasses
      # implement.
      #
      # @param event [Event]
      sig { abstract.params(event: Event).void }
      def apply(event); end

      # Hydrate the aggregate's state from a checkpoint's serialized state, so
      # that replaying only the events after the checkpoint gives the same
      # result as replaying the whole stream. Subclasses implement.
      #
      # @param state [Hash{String => Object}] the serialized state from a
      #   checkpoint
      sig { abstract.params(state: T::Hash[String, T.untyped]).void }
      def restore(state); end

      # The aggregate's state, serialized to a plain hash for a checkpoint.
      # Subclasses implement.
      #
      # @return [Hash{String => Object}]
      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def checkpoint_state; end

      # The keys of checkpoint_state that hold personal data and must be
      # encrypted at rest in a durable checkpoint store. The declaration lives
      # in the domain because it is a business rule — a statement of what the
      # law requires to be erasable — the same as Event.pii_fields; the
      # encryption that honours it lives in an adapter. Subclasses with personal
      # data in their state override.
      #
      # @return [Array<Symbol>]
      sig { returns(T::Array[Symbol]) }
      def self.checkpoint_pii_fields
        []
      end

      # The checkpoint to persist, or nil if one is not yet due. A checkpoint
      # is due when the stream's version is a positive multiple of
      # CHECKPOINT_INTERVAL — every hundred events. It carries the aggregate's
      # state at that version, so a later replay can restore from it and apply
      # only the events after.
      #
      # @return [Checkpoint, nil]
      sig { returns(T.nilable(Checkpoint)) }
      def checkpoint
        version = pending_version
        return nil unless version.positive? && (version % CHECKPOINT_INTERVAL).zero?

        Checkpoint.new(state: checkpoint_state, version: version)
      end

      # Record the position a replayed event came from. Used during replay so
      # expected_version reflects the committed stream, not locally-recorded
      # events.
      #
      # @param sequence [Integer]
      sig { params(sequence: Integer).void }
      def advance_to(sequence)
        @expected_version = sequence
      end

      private

      # The version the stream will be at once the aggregate's uncommitted
      # events are appended: the last recorded event's sequence, or the current
      # expected version if nothing is recorded.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def pending_version
        event = uncommitted_events.last
        event.nil? ? expected_version : event.sequence
      end

      # Stage an event produced by a command and fold it into state. The event
      # must already carry its sequence. Called by subclasses.
      #
      # @param event [Event]
      sig { params(event: Event).void }
      def record(event)
        @uncommitted_events << event
        apply(event)
      end
    end
  end
end
