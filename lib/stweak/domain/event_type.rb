# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'error'

module Stweak
  module Domain
    # The name an event is known by in the log: the type written on every
    # serialized event and the key the durable registry rebuilds it under. A
    # named type rather than a bare String, so a signature that asks for an
    # event type cannot be handed an arbitrary string, and the registry's keys
    # are the same kind of value as the type an event reports.
    #
    # Validated for shape at construction: it must be ASCII letters and digits,
    # starting with a letter, as in `AccountCreated`. That charset keeps the
    # name a plain identifier, with no whitespace or punctuation to trip a
    # log reader or a registry lookup. The name is not personal data, so it
    # renders plainly.
    #
    # Equality is by value: two event types are equal when they are exactly the
    # same class carrying the same string. It carries no shared base with the
    # other value objects by design, so each stands on its own.
    class EventType
      extend T::Sig

      # A valid event type: an ASCII letter followed by letters and digits.
      PATTERN = /\A[A-Za-z][A-Za-z0-9]*\z/

      sig { returns(String) }
      attr_reader :value

      # @param value [String] the event type name, which must match {PATTERN}
      # @raise [Stweak::Domain::ValidationError] if value does not match {PATTERN}
      sig { params(value: String).void }
      def initialize(value:)
        # `valid_encoding?` short-circuits the regex: on a non-UTF-8 string,
        # `match?` itself raises ArgumentError rather than returning false.
        valid = value.valid_encoding? && value.match?(PATTERN)
        raise ValidationError, "event type must be letters and digits, got: #{value.inspect}" unless valid

        @value = value
      end

      # The event type as a plain string.
      #
      # @return [String]
      sig { returns(String) }
      def to_s
        value
      end

      # Two event types are equal when they are exactly the same class carrying
      # the same value.
      #
      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.instance_of?(self.class)

        value == other.value
      end

      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        self == other
      end

      # Consistent with #eql?, so event types work as hash keys.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def hash
        value.hash
      end
    end
  end
end
