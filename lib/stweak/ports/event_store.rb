# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/aggregate'
require_relative '../domain/error'
require_relative '../domain/event'
require_relative '../domain/id'

module Stweak
  # Ports: the interfaces the domain relies on for the technology around it.
  # Adapters implement these; the domain depends on them and nothing else.
  module Ports
    # Raised when an append's expected_version does not match the stream's
    # current version, meaning the caller built on state that has since moved.
    # A conflict, in the domain taxonomy: appending on top of state that has
    # moved is a clash with a concurrent write.
    class ConcurrencyError < Stweak::Domain::ConflictError; end

    # The port an event store implements: append events to a stream at an
    # expected version, or read a stream back in order. The domain depends on
    # this interface and nothing else about how events are kept.
    #
    # Streams are qualified by the aggregate class that owns them, for the same
    # reason keys are: the project cannot assume that different kinds of
    # aggregate — an Account, a Player — have globally unique ids, and two that
    # happen to share an id must not share a stream.
    module EventStore
      extend T::Sig
      extend T::Helpers

      interface!

      # Append events to a stream. The append also emits the events to the
      # store's subscription, so the read side is kept current without the
      # caller knowing anything about listeners.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   the stream belongs to
      # @param stream_id [Stweak::Domain::Id] the stream to append to
      # @param expected_version [Integer] the stream version the caller built on
      # @param events [Array<Stweak::Domain::Event>]
      # @raise [ConcurrencyError] if the stream is no longer at expected_version
      sig do
        abstract
          .params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            expected_version: Integer,
            events: T::Array[Stweak::Domain::Event]
          )
          .void
      end
      def append(owner_type:, stream_id:, expected_version:, events:); end

      # Read a stream back in order.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   the stream belongs to
      # @param stream_id [Stweak::Domain::Id] the stream to read
      # @return [Array<Stweak::Domain::Event>]
      sig do
        abstract
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), stream_id: Stweak::Domain::Id)
          .returns(T::Array[Stweak::Domain::Event])
      end
      def read_stream(owner_type:, stream_id:); end

      # Yield every stream's events, in per-stream sequence order, together
      # with the owner they belong to. A projection system uses this to bring
      # a projection current or rebuild it from every stream, in the absence
      # of a global log to read.
      #
      # @yield [owner_type, stream_id, events]
      # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
      # anonymous `&`; the named block parameter is required to match the sig.
      sig do
        abstract
          .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                     stream_id: Stweak::Domain::Id,
                                     events: T::Array[Stweak::Domain::Event]).void)
          .void
      end
      def each_stream(&blk); end

      # Yield each stream without decrypting encrypted event fields.
      #
      # @yield [owner_type, stream_id, events]
      # rubocop:disable Naming/BlockForwarding
      sig do
        abstract
          .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                     stream_id: Stweak::Domain::Id,
                                     events: T::Array[Stweak::Domain::Event]).void)
          .void
      end
      def each_encrypted_stream(&blk); end
    end
  end
end
