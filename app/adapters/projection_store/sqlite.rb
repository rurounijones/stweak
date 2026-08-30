# typed: strict
# frozen_string_literal: true

require 'sqlite3'
require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # The durable, relational projection store: the real implementation of
    # Stweak::Ports::ProjectionStore, living alongside the domain gem's
    # in-memory one to prove the port is interchangeable. Cursors are one
    # indexed row per (projection, stream); each read model is its own table,
    # so the database looks like a normal application database rather than a
    # keyed JSON store. A projection's state is never a blob: it is the rows of
    # its table, written by the projector that maintains it.
    #
    # rubocop:disable Metrics/ClassLength -- the store's own operations plus a
    # keyed read and the table machinery; each method is the point of the port.
    class SqliteProjectionStore
      include Stweak::Ports::ProjectionStore

      extend T::Sig

      # Each read-model table's primary key column, so rows can be upserted and
      # deleted without the caller naming it twice.
      PRIMARY_KEYS = T.let({ accounts: :account_id }.freeze, T::Hash[Symbol, Symbol])

      # @param db [SQLite3::Database] the database to store projections in;
      #   the caller owns it and its lifecycle
      sig { params(db: SQLite3::Database).void }
      def initialize(db:)
        @db = db
        @db.results_as_hash = true
        create_tables
      end

      # @param projection_name [String]
      # @return [Hash{String => Integer}, nil]
      sig { override.params(projection_name: String).returns(T.nilable(T::Hash[String, Integer])) }
      def read(projection_name:)
        rows = @db.execute(
          'SELECT stream_key, sequence FROM projection_cursors WHERE projection_name = ?',
          [projection_name]
        )
        return nil if rows.empty?

        rows.to_h { |row| [row.fetch('stream_key'), row.fetch('sequence')] }
      end

      # @param projection_name [String]
      # @param cursors [Hash{String => Integer}]
      sig { override.params(projection_name: String, cursors: T::Hash[String, Integer]).void }
      def write(projection_name:, cursors:)
        @db.transaction do
          cursors.each do |stream_key, sequence|
            @db.execute(
              'INSERT OR REPLACE INTO projection_cursors (projection_name, stream_key, sequence) VALUES (?, ?, ?)',
              [projection_name, stream_key, sequence]
            )
          end
        end
      end

      # @param projection_name [String]
      sig { override.params(projection_name: String).void }
      def delete(projection_name:)
        @db.execute('DELETE FROM projection_cursors WHERE projection_name = ?', [projection_name])
      end

      # @param table [Symbol]
      # @param attributes [Hash{Symbol => Object}]
      sig { override.params(table: Symbol, attributes: T::Hash[Symbol, T.untyped]).void }
      def upsert(table:, attributes:)
        assert_table!(table)
        columns = attributes.keys.map(&:to_s)
        placeholders = columns.map { '?' }.join(', ')
        values = attributes.values.map { |value| to_stored_value(value) }
        @db.execute("INSERT OR REPLACE INTO #{table} (#{columns.join(', ')}) VALUES (#{placeholders})", values)
      end

      # SQLite cannot bind Ruby booleans, so the lifecycle flag round-trips as
      # its integer form; every other value binds as itself.
      sig { params(value: T.untyped).returns(T.untyped) }
      def to_stored_value(value)
        case value
        when true then 1
        when false then 0
        else value
        end
      end

      # @param table [Symbol]
      # @param id [String]
      sig { override.params(table: Symbol, id: String).void }
      def delete_row(table:, id:)
        assert_table!(table)
        @db.execute("DELETE FROM #{table} WHERE #{primary_key(table)} = ?", [id])
      end

      # @param table [Symbol]
      sig { override.params(table: Symbol).void }
      def clear(table:)
        assert_table!(table)
        @db.execute("DELETE FROM #{table}")
      end

      # @param table [Symbol]
      # @return [Array<Hash{Symbol => Object}>]
      sig { override.params(table: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def read_all(table:)
        assert_table!(table)
        @db.execute("SELECT * FROM #{table}").map { |row| row.transform_keys(&:to_sym) }
      end

      # @param table [Symbol]
      # @param id [String]
      # @return [Hash{Symbol => Object}, nil]
      sig { override.params(table: Symbol, id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def read_row(table:, id:)
        assert_table!(table)
        row = @db.execute("SELECT * FROM #{table} WHERE #{primary_key(table)} = ? LIMIT 1", [id]).first
        row&.transform_keys(&:to_sym)
      end

      private

      sig { void }
      def create_tables
        create_cursor_table
        create_accounts_table
      end

      sig { void }
      def create_cursor_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS projection_cursors (
            projection_name TEXT    NOT NULL,
            stream_key      TEXT    NOT NULL,
            sequence        INTEGER NOT NULL,
            PRIMARY KEY (projection_name, stream_key)
          )
        SQL
      end

      # rubocop:disable Metrics/MethodLength -- a table's columns are one per line
      sig { void }
      def create_accounts_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS accounts (
            account_id     TEXT PRIMARY KEY,
            username       TEXT NOT NULL,
            disabled       INTEGER NOT NULL DEFAULT 0,
            password_hash  TEXT NOT NULL,
            name_cipher    TEXT NOT NULL,
            email_cipher   TEXT NOT NULL,
            created_at     TEXT NOT NULL
          )
        SQL
      end
      # rubocop:enable Metrics/MethodLength

      # @param table [Symbol]
      # @raise [ArgumentError] if the store does not host the table
      sig { params(table: Symbol).void }
      def assert_table!(table)
        return if PRIMARY_KEYS.key?(table)

        raise ArgumentError, "no read-model table named #{table}"
      end

      # @param table [Symbol]
      # @return [Symbol]
      sig { params(table: Symbol).returns(Symbol) }
      def primary_key(table)
        PRIMARY_KEYS.fetch(table)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
