# typed: strict
# frozen_string_literal: true

require 'json'
require 'aws-sdk-dynamodb'
require 'sorbet-runtime'
require 'stweak'
require_relative '../event_serialization'

module App
  module Adapters
    # An event store backed by DynamoDB: the real, durable implementation of
    # Stweak::Ports::EventStore, living alongside the domain gem's in-memory
    # one to prove the port is interchangeable. One table carries every
    # stream, keyed by (owner, sequence); there is no global log. An append is
    # a single transaction that checks the stream's version and writes the
    # events, so optimistic concurrency is enforced without any cross-stream
    # contention. Events are stored as their serialized form plus their full
    # class name, and rebuilt on read.
    #
    # rubocop:disable Metrics/ClassLength -- the store implements the port;
    # the transaction assembly is the point.
    class DynamoDBEventStore
      include Stweak::Ports::EventStore
      include App::Adapters::EventSerialization

      extend T::Sig

      # @param client [Aws::DynamoDB::Client] the client to use; the caller
      #   points it at dynamodb-local or a real endpoint
      # @param streams_table [String] the table holding each stream's events
      # @param subscription [Stweak::Ports::EventSubscription, nil] the channel
      #   to publish appends to, or nil to keep the store silent
      sig do
        params(
          client: Aws::DynamoDB::Client,
          streams_table: String,
          subscription: T.nilable(Stweak::Ports::EventSubscription)
        ).void
      end
      def initialize(client:, streams_table:, subscription: nil)
        @client = client
        @streams_table = streams_table
        @subscription = subscription
        @existing_tables = T.let(load_table_names, T::Array[String])
        create_tables
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @param expected_version [Integer]
      # @param events [Array<Stweak::Domain::Event>]
      # @raise [Stweak::Ports::ConcurrencyError] if the stream is no longer at
      #   expected_version
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
        transaction = append_transaction(owner_type, stream_id, expected_version, events)
        @client.transact_write_items(transact_items: transaction)
        @subscription&.publish(events: events)
      rescue Aws::DynamoDB::Errors::TransactionCanceledException
        raise Stweak::Ports::ConcurrencyError
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @param after [Integer] the exclusive lower bound on sequence; 0 reads
      #   the whole stream. A range read straight on the sort key, so a resumed
      #   aggregate reads only the events after its checkpoint.
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
        @client.query(
          table_name: @streams_table,
          key_condition_expression: 'pk = :pk AND sk > :after',
          expression_attribute_values: { ':pk' => stream_key(owner_type, stream_id), ':after' => after }
        ).items.map { |item| deserialize(item.fetch('data')) }
      end

      # @yield [owner_type, stream_id, events]
      # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- srb tc does
      # not recognise anonymous `&`; the named block parameter is required to match the sig.
      sig do
        override
          .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                     stream_id: Stweak::Domain::Id,
                                     events: T::Array[Stweak::Domain::Event]).void)
          .void
      end
      def each_stream(&blk)
        streams_from_scan.each(&blk)
      end

      # Yield streams in their stored form. Encrypted event fields remain
      # ciphertext, allowing a projection that understands that representation
      # to catch up without loading encryption keys.
      #
      # @yield [owner_type, stream_id, events]
      sig do
        override
          .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                     stream_id: Stweak::Domain::Id,
                                     events: T::Array[Stweak::Domain::Event]).void)
          .void
      end
      def each_encrypted_stream(&blk)
        streams_from_scan.each(&blk)
      end

      # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

      # Every stream's events, rebuilt from the stored form, with the owner
      # and id the stream belongs to.
      #
      # @return [Array<[Class<Stweak::Domain::Aggregate>, Stweak::Domain::Id, Array<Stweak::Domain::Event>]>]
      sig do
        returns(
          T::Array[
            [
              T.class_of(Stweak::Domain::Aggregate),
              Stweak::Domain::Id,
              T::Array[Stweak::Domain::Event]
            ]
          ]
        )
      end
      def streams_from_scan
        @client.scan(table_name: @streams_table).items
               .select { |item| item.fetch('sk').positive? }
               .group_by { |item| item.fetch('pk') }
               .values
               .map { |stream_items| stream_tuple(stream_items) }
      end

      # One stream's events, together with its owner and id.
      #
      # @param stream_items [Array<Hash>] the stream's items in scan order
      # @return [Array(Class<Stweak::Domain::Aggregate>, Stweak::Domain::Id, Array<Stweak::Domain::Event>)]
      sig do
        params(stream_items: T::Array[T::Hash[String, T.untyped]])
          .returns([T.class_of(Stweak::Domain::Aggregate), Stweak::Domain::Id, T::Array[Stweak::Domain::Event]])
      end
      def stream_tuple(stream_items)
        events = stream_items.sort_by { |item| item.fetch('sk') }
                             .map { |item| deserialize(item.fetch('data')) }
        owner_type = Stweak::Domain::OwnerRegistry.owner_type_for(events.first.class)
        [owner_type, events.first.stream_id, events]
      end

      private

      # The transaction: the version check and the stream writes, so the
      # append is atomic. There is no global log to write or counter to
      # advance, so appends to different streams never contend.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @param expected_version [Integer]
      # @param events [Array<Stweak::Domain::Event>]
      # @return [Array<Hash>]
      sig do
        params(
          owner_type: T.class_of(Stweak::Domain::Aggregate),
          stream_id: Stweak::Domain::Id,
          expected_version: Integer,
          events: T::Array[Stweak::Domain::Event]
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def append_transaction(owner_type, stream_id, expected_version, events)
        version_update(owner_type, stream_id, expected_version, events.length) +
          stream_puts(owner_type, stream_id, events)
      end

      # The transaction item that checks the stream's version and advances it.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @param expected_version [Integer]
      # @param count [Integer]
      # @return [Array<Hash>]
      sig do
        params(
          owner_type: T.class_of(Stweak::Domain::Aggregate),
          stream_id: Stweak::Domain::Id,
          expected_version: Integer,
          count: Integer
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def version_update(owner_type, stream_id, expected_version, count)
        [{
          update: {
            table_name: @streams_table,
            key: { 'pk' => stream_key(owner_type, stream_id), 'sk' => 0 },
            update_expression: 'SET #version = :version',
            condition_expression: 'attribute_not_exists(#version) OR #version = :expected',
            expression_attribute_names: { '#version' => 'version' },
            expression_attribute_values: { ':version' => expected_version + count, ':expected' => expected_version }
          }
        }]
      end

      # The transaction items that write each event to its stream.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @param events [Array<Stweak::Domain::Event>]
      # @return [Array<Hash>]
      sig do
        params(
          owner_type: T.class_of(Stweak::Domain::Aggregate),
          stream_id: Stweak::Domain::Id,
          events: T::Array[Stweak::Domain::Event]
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def stream_puts(owner_type, stream_id, events)
        events.map do |event|
          {
            put: {
              table_name: @streams_table,
              item: { 'pk' => stream_key(owner_type, stream_id), 'sk' => event.sequence, 'data' => serialize(event) },
              condition_expression: 'attribute_not_exists(sk)'
            }
          }
        end
      end

      # The stream's partition key: owner class and id, so an Account and a
      # Player that happen to share an id never share a stream.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param stream_id [Stweak::Domain::Id]
      # @return [String]
      sig do
        params(owner_type: T.class_of(Stweak::Domain::Aggregate), stream_id: Stweak::Domain::Id)
          .returns(String)
      end
      def stream_key(owner_type, stream_id)
        "#{owner_type.name}##{stream_id}"
      end

      # Create the streams table if it does not exist. Idempotent: an
      # existing table is left alone.
      sig { void }
      def create_tables
        create_table(@streams_table, 'pk', 'sk')
      end

      # Create one table if it does not exist.
      #
      # @param table_name [String]
      # @param partition_key [String]
      # @param sort_key [String]
      sig { params(table_name: String, partition_key: String, sort_key: String).void }
      def create_table(table_name, partition_key, sort_key)
        return if table_exists?(table_name)

        create_missing_table(table_name, partition_key, sort_key)
      end

      # Whether the table was present in the ListTables snapshot read at
      # construction. The snapshot is read once, so checking or creating any
      # number of tables issues no further ListTables calls.
      sig { params(table_name: String).returns(T::Boolean) }
      def table_exists?(table_name)
        @existing_tables.include?(table_name)
      end

      # Every existing table name, read from ListTables once and following
      # pagination when DynamoDB returns more than one page. ListTables is used
      # rather than DescribeTable because DescribeTable's expected missing-table
      # response is recorded as an ERROR by the AWS SDK instrumentation.
      sig { returns(T::Array[String]) }
      def load_table_names
        names = []
        response = @client.list_tables
        loop do
          names.concat(response.table_names)
          break unless response.last_evaluated_table_name

          response = @client.list_tables(exclusive_start_table_name: response.last_evaluated_table_name)
        end
        names
      end

      # Create a table after list_tables confirmed it is absent. The rescue
      # still handles two processes discovering the absence concurrently.
      #
      # @param table_name [String]
      # @param partition_key [String]
      # @param sort_key [String]
      # rubocop:disable Metrics/MethodLength -- table schema is one operation
      sig { params(table_name: String, partition_key: String, sort_key: String).void }
      def create_missing_table(table_name, partition_key, sort_key)
        @client.create_table(
          table_name: table_name,
          key_schema: [
            { attribute_name: partition_key, key_type: 'HASH' },
            { attribute_name: sort_key, key_type: 'RANGE' }
          ],
          attribute_definitions: [
            { attribute_name: partition_key, attribute_type: 'S' },
            { attribute_name: sort_key, attribute_type: 'N' }
          ],
          billing_mode: 'PAY_PER_REQUEST'
        )
      rescue Aws::DynamoDB::Errors::ResourceInUseException
        nil
      end
      # rubocop:enable Metrics/MethodLength
    end
    # rubocop:enable Metrics/ClassLength
  end
end
