# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Ports
    # The port a projection store implements: durable, relational storage for
    # projections. It has two faces. The projection system persists each
    # projection's per-stream cursors here — the position it is current to, so a
    # restarted projection resumes from each stream's cursor instead of
    # replaying the whole log. And a projection's materialized state lives here
    # too, not as a serialized blob but as rows in the store's tables: the
    # projector that maintains a read model — an accounts table, a balance, a
    # count — writes rows through the row operations, and the tables look like a
    # normal application database rather than a keyed JSON store. The event log
    # remains the source of truth: every stored cursor and row is derived data,
    # discardable and rebuildable at any time.
    module ProjectionStore
      extend T::Sig
      extend T::Helpers

      interface!

      # A projection's stored per-stream cursors, or nil if it has never been
      # stored.
      #
      # @param projection_name [String] the projection's stable name
      # @return [Hash{String => Integer}, nil] each stream the projection has
      #   consumed from, mapped to the highest sequence applied, or nil if the
      #   projection has never been stored
      sig { abstract.params(projection_name: String).returns(T.nilable(T::Hash[String, Integer])) }
      def read(projection_name:); end

      # Replace a projection's stored cursors. The store keeps a snapshot of the
      # cursors rather than retaining the caller's hash, so a later in-place
      # advance of the passed hash is not observed as if it had been persisted.
      #
      # @param projection_name [String] the projection's stable name
      # @param cursors [Hash{String => Integer}] each stream mapped to the
      #   highest sequence applied
      sig { abstract.params(projection_name: String, cursors: T::Hash[String, Integer]).void }
      def write(projection_name:, cursors:); end

      # Delete a projection's stored cursors. Deleting a missing projection does
      # not raise.
      #
      # @param projection_name [String] the projection's stable name
      sig { abstract.params(projection_name: String).void }
      def delete(projection_name:); end

      # Insert or update a row in a read-model table, keyed by the table's
      # primary key. Idempotent: re-upserting the same key replaces the row, so
      # a projector is safe under the subscription's at-least-once delivery.
      #
      # @param table [Symbol] the read-model table
      # @param attributes [Hash{Symbol => Object}] the row's columns and values,
      #   including the primary key
      sig { abstract.params(table: Symbol, attributes: T::Hash[Symbol, T.untyped]).void }
      def upsert(table:, attributes:); end

      # Delete a row by its primary key. Deleting a missing row does not raise.
      #
      # @param table [Symbol] the read-model table
      # @param id [String] the row's primary key value
      sig { abstract.params(table: Symbol, id: String).void }
      def delete_row(table:, id:); end

      # Remove every row from a read-model table. Used when a projection is
      # rebuilt from the beginning of the log.
      #
      # @param table [Symbol] the read-model table
      sig { abstract.params(table: Symbol).void }
      def clear(table:); end

      # Every row in a read-model table, keyed by column.
      #
      # @param table [Symbol] the read-model table
      # @return [Array<Hash{Symbol => Object}>]
      sig { abstract.params(table: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def read_all(table:); end

      # One row from a read-model table by its primary key, or nil if no row has
      # that key. This is the keyed read a "show one account" view needs, so it
      # does not scan and decrypt the whole table to answer a question about a
      # single row.
      #
      # @param table [Symbol] the read-model table
      # @param id [String] the row's primary key value
      # @return [Hash{Symbol => Object}, nil]
      sig { abstract.params(table: Symbol, id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def read_row(table:, id:); end
    end
  end
end
