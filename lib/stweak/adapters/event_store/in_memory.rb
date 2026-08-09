# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../domain/aggregate'
require_relative '../../domain/event'
require_relative '../../domain/id'
require_relative '../../ports/event_store'
require_relative '../../ports/event_subscription'

module Stweak
  module Adapters
    # Event store adapters.
    module EventStore
      # The simplest event store: per-stream event lists in memory, qualified
      # by the aggregate class that owns the stream so that an Account and a
      # Player that happen to share an id never share a stream. When given a
      # subscription it publishes every append to it — the in-memory
      # equivalent of a transport such as an SQS queue carrying the events to
      # listeners. Thread-safe and adequate for tests and local work, but
      # nothing survives a restart.
      #
      # rubocop:disable Metrics/ClassLength -- the store implements the port
      # and the emit side of append delivery; the extra methods are the point.
      class InMemoryEventStore
        include Stweak::Ports::EventStore

        extend T::Sig

        # @param subscription [Stweak::Ports::EventSubscription, nil] the
        #   channel to publish appends to, or nil to keep the store silent
        sig { params(subscription: T.nilable(Stweak::Ports::EventSubscription)).void }
        def initialize(subscription: nil)
          @streams = T.let(
            {},
            T::Hash[T.class_of(Stweak::Domain::Aggregate), T::Hash[Stweak::Domain::Id, T::Array[Stweak::Domain::Event]]]
          )
          @subscription = subscription
          @mutex = T.let(Mutex.new, Mutex)
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param expected_version [Integer]
        # @param events [Array<Stweak::Domain::Event>]
        # @raise [Stweak::Ports::ConcurrencyError] if the stream has moved on,
        #   or an event is not the next in sequence
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              stream_id: Stweak::Domain::Id,
              expected_version: Integer,
              events: T::Array[Stweak::Domain::Event]
            )
            .void
        end
        def append(owner_type:, stream_id:, expected_version:, events:)
          @mutex.synchronize do
            assert_version!(owner_type, stream_id, version_of(owner_type, stream_id), expected_version)
            append_to_stream(owner_type, stream_id, events)
          end
          @subscription&.publish(events: events)
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param after [Integer] the exclusive lower bound on sequence; 0 reads
        #   the whole stream
        # @return [Array<Stweak::Domain::Event>]
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              stream_id: Stweak::Domain::Id,
              after: Integer
            )
            .returns(T::Array[Stweak::Domain::Event])
        end
        def read_stream(owner_type:, stream_id:, after: 0)
          @mutex.synchronize do
            @streams.fetch(owner_type, {}).fetch(stream_id, []).select { |event| event.sequence > after }
          end
        end

        # @yield [owner_type, stream_id, events]
        # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
        # anonymous `&`; the named block parameter is required to match the sig.
        sig do
          override
            .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                       stream_id: Stweak::Domain::Id,
                                       events: T::Array[Stweak::Domain::Event]).void)
            .void
        end
        def each_stream(&blk)
          @mutex.synchronize do
            @streams.each do |owner_type, streams_by_id|
              streams_by_id.each do |stream_id, events|
                yield(owner_type, stream_id, events.dup)
              end
            end
          end
        end

        sig do
          override
            .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                       stream_id: Stweak::Domain::Id,
                                       events: T::Array[Stweak::Domain::Event]).void)
            .void
        end
        def each_encrypted_stream(&blk)
          each_stream(&blk)
        end

        # rubocop:enable Naming/BlockForwarding

        private

        # The streams for an owner type, creating the bucket on first use.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @return [Hash{Stweak::Domain::Id => Array<Stweak::Domain::Event>}]
        sig do
          params(owner_type: T.class_of(Stweak::Domain::Aggregate))
            .returns(T::Hash[Stweak::Domain::Id, T::Array[Stweak::Domain::Event]])
        end
        def streams_for_type(owner_type)
          streams = @streams[owner_type]
          return streams unless streams.nil?

          @streams[owner_type] = T.let({}, T::Hash[Stweak::Domain::Id, T::Array[Stweak::Domain::Event]])
          T.must(@streams[owner_type])
        end

        # The current version of a stream: how many events it holds.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @return [Integer]
        sig do
          params(owner_type: T.class_of(Stweak::Domain::Aggregate), stream_id: Stweak::Domain::Id)
            .returns(Integer)
        end
        def version_of(owner_type, stream_id)
          @streams.fetch(owner_type, {}).fetch(stream_id, []).length
        end

        # Append the events to their stream. Each event must be the next in
        # its stream's sequence; the stream's length is that sequence's
        # version, since the append version was already checked against it.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param events [Array<Stweak::Domain::Event>]
        sig do
          params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            events: T::Array[Stweak::Domain::Event]
          ).void
        end
        def append_to_stream(owner_type, stream_id, events)
          streams = streams_for_type(owner_type)
          events.each do |event|
            stream = streams[stream_id] ||= []
            assert_sequence!(owner_type, stream_id, stream.length, event)
            stream << event
          end
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param current [Integer]
        # @param expected [Integer]
        # @raise [Stweak::Ports::ConcurrencyError] if current and expected differ
        sig do
          params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            current: Integer,
            expected: Integer
          ).void
        end
        def assert_version!(owner_type, stream_id, current, expected)
          return if current == expected

          raise Stweak::Ports::ConcurrencyError,
                "stream #{owner_type}##{stream_id} is at version #{current}, not #{expected}"
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param current [Integer]
        # @param event [Stweak::Domain::Event]
        # @raise [Stweak::Ports::ConcurrencyError] if the event is not next
        sig do
          params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            current: Integer,
            event: Stweak::Domain::Event
          ).void
        end
        def assert_sequence!(owner_type, stream_id, current, event)
          return if event.sequence == current + 1

          raise Stweak::Ports::ConcurrencyError,
                "stream #{owner_type}##{stream_id}: event #{event.sequence} is not the next event after #{current}"
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
