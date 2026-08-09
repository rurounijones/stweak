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

      # The name the event is known by in the log, and the key the durable
      # registry rebuilds it under. Each event declares its own, so the name is
      # a deliberate, stable part of the serialized contract rather than
      # something derived from the class: two aggregates' events cannot collide
      # under a shared leaf name, and moving a class never rewrites the type of
      # events already in the log. Subclasses implement, returning their TYPE.
      #
      # @return [String] for example `"AccountCreated"`
      sig { abstract.returns(String) }
      def type; end

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

      # Translate an older serialized shape into the current one, so from_h only
      # ever deals with the current form. This is where an event's `version` is
      # consumed on read: reading an older event upcasts it before anything else
      # sees it, and the log is never rewritten — the stored bytes stay as they
      # were written and are translated only on the way out. The default is
      # identity, for an event whose shape has never changed. A subclass whose
      # schema changes overrides this, recognising an older form by its
      # `version` and returning the current-shape hash with `version` bumped. It
      # must not mutate its argument.
      #
      # @param hash [Hash{String => Object}] the serialized form as stored
      # @return [Hash{String => Object}] the same form translated to the current
      #   version
      sig { params(hash: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
      def self.upcast(hash)
        hash
      end

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
