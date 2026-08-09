# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'time'
require_relative 'error'
require_relative 'id'

module Stweak
  # The domain layer: the aggregates, events, commands, and rules that are the
  # point of the project. It knows nothing about the technology around it.
  module Domain
    # The base class for events: facts that have already happened and cannot be
    # argued with. Events are immutable value objects, and the log never
    # rewrites them; a correction is a new event, not an edit.
    #
    # Subclasses add their own fields, their own schema version, and the
    # serialization to rebuild them. This base provides the shared shape: the
    # stream the event belongs to, its position in that stream, when it
    # happened, and when it was committed.
    class Event
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(Id) }
      attr_reader :stream_id

      sig { returns(Integer) }
      attr_reader :sequence

      sig { returns(Time) }
      attr_reader :occurred_at

      # When the event was committed to the store. The aggregate defaults this
      # to occurred_at when it builds the event; the store stamps the true
      # write time just before the append.
      sig { returns(Time) }
      attr_reader :created_at

      # @param stream_id [Id] the stream this event belongs to
      # @param sequence [Integer] the event's position within its stream
      # @param occurred_at [Time] when the event happened
      # @param created_at [Time] when the event was committed, defaulting to
      #   occurred_at until the store stamps the true write time at append
      # @raise [ValidationError] if the sequence is not positive
      sig { params(stream_id: Id, sequence: Integer, occurred_at: Time, created_at: Time).void }
      def initialize(stream_id:, sequence:, occurred_at:, created_at: occurred_at)
        raise ValidationError, 'sequence must be positive' if sequence < 1

        @stream_id = stream_id
        @sequence = sequence
        @occurred_at = occurred_at
        @created_at = created_at
      end

      # The name the event is known by in the log, derived from its class.
      #
      # @return [String] for example `"AccountCreated"`
      sig { returns(String) }
      def type
        self.class.to_s.split('::').fetch(-1)
      end

      # The schema version of this event. Old versions are upcast on read; see
      # "Event versioning" in README.md. Subclasses implement.
      #
      # @return [Integer]
      sig { abstract.returns(Integer) }
      def version; end

      # Fields that hold personal data and must be encrypted at rest. The
      # declaration lives in the domain because it is a business rule; the
      # encryption that honours it lives in an adapter.
      #
      # @return [Array<Symbol>]
      sig { returns(T::Array[Symbol]) }
      def self.pii_fields
        []
      end

      # The event serialized to a plain hash, including its metadata. Adapters
      # use this to store or transform events.
      #
      # @return [Hash{String => Object}]
      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        {
          'type' => type,
          'version' => version,
          'stream_id' => stream_id.to_s,
          'sequence' => sequence,
          'occurred_at' => occurred_at.iso8601,
          'created_at' => created_at.iso8601
        }
      end

      # A copy of this event with some attributes replaced. Adapters use this
      # to transform field values, such as encrypting a PII field, without
      # mutating the original.
      #
      # @param attributes [Hash{String => Object}] the attributes to replace
      # @return [Event]
      sig { params(attributes: T::Hash[String, T.untyped]).returns(Event) }
      def with(attributes)
        self.class.from_h(to_h.merge(attributes))
      end

      # Rebuild an event from its serialized form. Subclasses implement.
      #
      # @param hash [Hash{String => Object}]
      # @return [Event]
      sig { abstract.params(hash: T::Hash[String, T.untyped]).returns(Event) }
      def self.from_h(hash); end

      # Two events are equal when they serialize identically.
      #
      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Event)

        to_h == other.to_h
      end

      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        self == other
      end

      # Consistent with #eql?, so events work as hash keys.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def hash
        to_h.hash
      end
    end
  end
end
