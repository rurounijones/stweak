# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'error'

module Stweak
  module Domain
    # The base class for the domain's identifier types. Holds the shared shape
    # of an id — a value validated as a UUID at construction, string rendering,
    # and value equality — so a concrete id like AccountId is a thin subclass.
    # Typing a field as Id means "an identifier"; typing it as AccountId means
    # "an account's identifier", and the type system carries the distinction.
    # Equality is by exact class and value: two ids are equal only when they are
    # the very same class carrying the same value, so an Account and a Player
    # that share an id are never conflated, and neither is an id conflated with
    # a subclass of it. Exact class rather than "same-or-subclass" is what keeps
    # equality symmetric — the contract Set, Array#== and hash keys rely on —
    # because a same-or-subclass rule makes `a == b` and `b == a` disagree the
    # moment b is a subclass of a.
    class Id
      extend T::Sig

      # A UUID in its canonical lowercase form.
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

      sig { returns(String) }
      attr_reader :value

      # @param value [String] the id, which must be a UUID
      # @raise [Stweak::Domain::ValidationError] if value is not a UUID
      sig { params(value: String).void }
      def initialize(value:)
        # `valid_encoding?` short-circuits the regex: on a non-UTF-8 string,
        # `match?` itself raises ArgumentError rather than returning false.
        valid_uuid = value.valid_encoding? && value.match?(UUID_PATTERN)
        raise ValidationError, "id must be a UUID, got: #{value.inspect}" unless valid_uuid

        @value = value
      end

      # The id as a plain string.
      #
      # @return [String]
      sig { returns(String) }
      def to_s
        value
      end

      # Two ids are equal when they are exactly the same class carrying the same
      # value. Exact class, not "an instance of my class", so equality stays
      # symmetric across the base/subclass boundary: an Id and an AccountId with
      # the same value are unequal both ways round, never one way only.
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

      # Consistent with #eql?, so ids work as hash keys.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def hash
        value.hash
      end
    end
  end
end
