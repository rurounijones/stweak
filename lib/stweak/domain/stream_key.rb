# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'error'

module Stweak
  module Domain
    # The key a projection's cursor is held under: one event stream, named by the
    # aggregate class that owns it and the stream's id, as in
    # `Stweak::Domain::Accounts::Account#00000000-0000-4000-8000-000000000001`.
    # The owner is part of the key so that two aggregates of different kinds
    # sharing an id never share a cursor. A named type rather than a bare String,
    # so a cursor operation cannot be handed an arbitrary string as a stream.
    #
    # Validated for shape at construction: the owner must be a Ruby constant path
    # and the id a canonical UUID, joined by a single `#`. The shape is checked on
    # the way back in as well as the way out, because a durable store rebuilds
    # these keys from text it was given earlier.
    #
    # Equality is by value: two stream keys are equal when they are exactly the
    # same class carrying the same string. It carries no shared base with the
    # other value objects by design, so each stands on its own.
    class StreamKey
      extend T::Sig

      # A valid stream key: a constant path, a `#`, then a canonical UUID.
      PATTERN = /\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*
        \#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/x

      sig { returns(String) }
      attr_reader :value

      # @param value [String] the stream key, which must match {PATTERN}
      # @raise [Stweak::Domain::ValidationError] if value does not match {PATTERN}
      sig { params(value: String).void }
      def initialize(value:)
        # `valid_encoding?` short-circuits the regex: on a non-UTF-8 string,
        # `match?` itself raises ArgumentError rather than returning false.
        valid = value.valid_encoding? && value.match?(PATTERN)
        raise ValidationError, "stream key must be an owner and a UUID joined by #, got: #{value.inspect}" unless valid

        @value = value
      end

      # The stream key as a plain string.
      #
      # @return [String]
      sig { returns(String) }
      def to_s
        value
      end

      # Two stream keys are equal when they are exactly the same class carrying
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

      # Consistent with #eql?, so stream keys work as hash keys.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def hash
        value.hash
      end
    end
  end
end
