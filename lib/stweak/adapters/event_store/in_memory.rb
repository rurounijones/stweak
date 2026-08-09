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

        # A stored event: the event's class and its serialized form. Holding the
        # serialized form rather than the live object makes the store round-trip
        # through serialization on read, exactly as the durable store does, so
        # an older-version event is upcast on read here too. The class captured
        # at append is the current class for the event's type, since there is
        # only ever one class per type, so no type-name registry is needed.
        Stored = T.type_alias { [T.class_of(Stweak::Domain::Event), T::Hash[String, T.untyped]] }

        # The map from owner type to its streams: for each owner type, a map
        # from stream id to that stream's stored events.
        StreamMap = T.type_alias do
          T::Hash[T.class_of(Stweak::Domain::Aggregate), T::Hash[Stweak::Domain::Id, T::Array[Stored]]]
        end

        # @param subscription [Stweak::Ports::EventSubscription, nil] the
        #   channel to publish appends to, or nil to keep the store silent
        sig { params(subscription: T.nilable(Stweak::Ports::EventSubscription)).void }
        def initialize(subscription: nil)
          @streams = T.let({}, StreamMap)
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
          write(owner_type, stream_id, expected_version, events)
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
          @mutex.synchronize { stream_after(owner_type, stream_id, after) }
        end

        # @yield [owner_type, stream_id, events]
        # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding
        # -- srb tc does not recognise anonymous `&`; the named block parameter
        # is required to match the sig and to forward to #emit_streams.
        sig do
          override
            .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                       stream_id: Stweak::Domain::Id,
                                       events: T::Array[Stweak::Domain::Event]).void)
            .void
        end
        def each_stream(&blk)
          @mutex.synchronize { emit_streams(&blk) }
        end
        # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

        private

        # Rebuild a stored event from its serialized form, upcasting an older
        # shape to the current one before from_h sees it — the read-path
        # translation the durable store performs too.
        #
        # @param entry [Stored]
        # @return [Stweak::Domain::Event]
        sig { params(entry: Stored).returns(Stweak::Domain::Event) }
        def rebuild(entry)
          klass, hash = entry
          klass.from_h(klass.upcast(hash))
        end

        # The write side of append under the stream lock: check the expected
        # version, then append in sequence. Isolated so that #append's only
        # mutation is the testable delegation and publish, and this thin lock
        # wrapper — whose sole surviving mutation is dropping @mutex.synchronize,
        # which no single-threaded test can observe — carries the equivalent.
        # The version check and the append it guards are pinned by the stale,
        # out-of-sequence and append-and-read specs, and are fully mutated in
        # #assert_version! and #append_to_stream. Ignored in .mutant.yml.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param expected_version [Integer]
        # @param events [Array<Stweak::Domain::Event>]
        sig do
          params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            expected_version: Integer,
            events: T::Array[Stweak::Domain::Event]
          ).void
        end
        def write(owner_type, stream_id, expected_version, events)
          @mutex.synchronize do
            assert_version!(owner_type, stream_id, version_of(owner_type, stream_id), expected_version)
            append_to_stream(owner_type, stream_id, events)
          end
        end

        # The events on a stream after a given sequence, rebuilt. Holds the read
        # filter so that #read_stream is a thin lock wrapper carrying only the
        # two equivalents no test can kill — the dropped @mutex.synchronize and
        # the +after: 0+ default, which, since sequences are one-based, selects
        # the same events as any negative bound. The +> after+ comparison and
        # the rebuild here are fully mutated, pinned by the after-sequence specs.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param stream_id [Stweak::Domain::Id]
        # @param after [Integer]
        # @return [Array<Stweak::Domain::Event>]
        sig do
          params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            stream_id: Stweak::Domain::Id,
            after: Integer
          ).returns(T::Array[Stweak::Domain::Event])
        end
        def stream_after(owner_type, stream_id, after)
          @streams.fetch(owner_type, {}).fetch(stream_id, [])
                  .map { |entry| rebuild(entry) }
                  .select { |event| event.sequence > after }
        end

        # Yield each stream with its owner and rebuilt events. Holds the
        # iteration so that #each_stream is a thin lock wrapper whose only
        # surviving mutation is the dropped @mutex.synchronize. The yielded owner
        # type, stream id and events are fully mutated here, pinned by the
        # each-stream specs.
        #
        # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
        # anonymous `&`; the named block parameter is required to match the sig.
        sig do
          params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                    stream_id: Stweak::Domain::Id,
                                    events: T::Array[Stweak::Domain::Event]).void)
            .void
        end
        def emit_streams(&blk)
          @streams.each do |owner_type, streams_by_id|
            streams_by_id.each do |stream_id, entries|
              yield(owner_type, stream_id, entries.map { |entry| rebuild(entry) })
            end
          end
        end
        # rubocop:enable Naming/BlockForwarding

        # The streams for an owner type, creating the bucket on first use.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @return [Hash{Stweak::Domain::Id => Array<Stored>}]
        sig do
          params(owner_type: T.class_of(Stweak::Domain::Aggregate))
            .returns(T::Hash[Stweak::Domain::Id, T::Array[Stored]])
        end
        def streams_for_type(owner_type)
          @streams[owner_type] ||= {}
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
            stream << [event.class, event.to_h]
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

          raise Ports::ConcurrencyError,
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

          raise Ports::ConcurrencyError,
                "stream #{owner_type}##{stream_id}: event #{event.sequence} is not the next event after #{current}"
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
