# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'event'
require_relative 'id'

module Stweak
  module Domain
    # The base class for aggregates: the unit a command is addressed to and
    # that guards the rules. An aggregate is rebuilt by replaying its own event
    # stream, decides whether a command is allowed, and emits the events that
    # follow from allowing it. Rules can be enforced within one aggregate; rules
    # spanning several aggregates are handled elsewhere.
    class Aggregate
      extend T::Sig
      extend T::Helpers

      abstract!

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

      # Rebuild an aggregate from its stream. The stream's events are applied
      # in order and the aggregate's expected version tracks the last one.
      #
      # @param id [Id]
      # @param events [Array<Event>] the events in the stream, in order
      # @return [Aggregate] an instance of the class replay is called on
      sig { params(id: Id, events: T::Array[Event]).returns(T.attached_class) }
      def self.replay(id:, events:)
        aggregate = new(id: id)
        events.each do |event|
          aggregate.apply(event)
          aggregate.advance_to(event.sequence)
        end
        aggregate
      end

      # Fold an event into the aggregate's state. Called for every event on
      # replay and for every event the aggregate records itself. Subclasses
      # implement.
      #
      # @param event [Event]
      sig { abstract.params(event: Event).void }
      def apply(event); end

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
