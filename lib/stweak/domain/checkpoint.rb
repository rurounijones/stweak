# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'error'

module Stweak
  module Domain
    # A checkpoint: a cached copy of an aggregate's state, taken at a point in
    # its stream. The write side writes one every 100 events, so that a command
    # handler can resume an aggregate from its latest checkpoint plus only the
    # events after it, rather than by replaying the whole stream. A checkpoint
    # is derived data: the event log remains the source of truth, and any
    # checkpoint can be discarded and rebuilt.
    class Checkpoint
      extend T::Sig

      # The aggregate's state, serialized to a plain hash.
      #
      # @return [Hash{String => Object}]
      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :state

      # The stream position the state reflects: how many of the aggregate's
      # events the checkpoint is current to. Replaying the events after this
      # version brings the state back up to date.
      #
      # @return [Integer]
      sig { returns(Integer) }
      attr_reader :version

      # @param state [Hash{String => Object}] the aggregate's state, serialized
      # @param version [Integer] the stream position the state reflects
      # @raise [Stweak::Domain::ValidationError] if the version is negative
      sig { params(state: T::Hash[String, T.untyped], version: Integer).void }
      def initialize(state:, version:)
        raise ValidationError, 'version must not be negative' if version.negative?

        @state = state
        @version = version
      end

      # Two checkpoints are equal when they carry the same state at the same
      # version.
      #
      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Checkpoint)

        state == other.state && version == other.version
      end

      # @param other [Object]
      # @return [Boolean]
      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        self == other
      end

      # Consistent with #eql?, so checkpoints work as hash keys.
      #
      # @return [Integer]
      sig { returns(Integer) }
      def hash
        [state, version].hash
      end
    end
  end
end
