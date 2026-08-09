# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../ports/projection_store'

module Stweak
  module Adapters
    # Projection store adapters.
    module ProjectionStore
      # The in-memory projection store: the counterpart to the durable SQLite
      # one, proving the port is interchangeable. Cursors are held per
      # projection as a hash of stream to sequence; each read-model table is a
      # hash of primary key to row. Rows and cursors are copied in on write and
      # copied out on read, so the store never shares a hash with the caller —
      # the round-trip the SQLite store gets from writing columns and building a
      # fresh row on every SELECT. Nothing survives a restart, which is accepted
      # while the domain gem has no durable collaborator of its own.
      class InMemoryProjectionStore
        include Stweak::Ports::ProjectionStore

        extend T::Sig

        # Each read-model table's primary key column, so rows can be keyed and
        # upserted without the caller naming it twice.
        PRIMARY_KEYS = T.let({ accounts: :account_id }.freeze, T::Hash[Symbol, Symbol])

        sig { void }
        def initialize
          @cursors = T.let({}, T::Hash[String, T::Hash[String, Integer]])
          @tables = T.let({}, T::Hash[Symbol, T::Hash[String, T::Hash[Symbol, T.untyped]]])
        end

        # @param projection_name [String]
        # @return [Hash{String => Integer}, nil]
        sig { override.params(projection_name: String).returns(T.nilable(T::Hash[String, Integer])) }
        def read(projection_name:)
          @cursors[projection_name]&.dup
        end

        # @param projection_name [String]
        # @param cursors [Hash{String => Integer}]
        sig { override.params(projection_name: String, cursors: T::Hash[String, Integer]).void }
        def write(projection_name:, cursors:)
          @cursors[projection_name] = cursors.dup
        end

        # @param projection_name [String]
        sig { override.params(projection_name: String).void }
        def delete(projection_name:)
          @cursors.delete(projection_name)
        end

        # @param table [Symbol]
        # @param attributes [Hash{Symbol => Object}]
        sig { override.params(table: Symbol, attributes: T::Hash[Symbol, T.untyped]).void }
        def upsert(table:, attributes:)
          rows = rows_for(table)
          rows[attributes.fetch(primary_key(table))] = attributes.dup
        end

        # @param table [Symbol]
        # @param id [String]
        sig { override.params(table: Symbol, id: String).void }
        def delete_row(table:, id:)
          rows_for(table).delete(id)
        end

        # @param table [Symbol]
        sig { override.params(table: Symbol).void }
        def clear(table:)
          rows_for(table).clear
        end

        # @param table [Symbol]
        # @return [Array<Hash{Symbol => Object}>]
        sig { override.params(table: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def read_all(table:)
          rows_for(table).values.map(&:dup)
        end

        # @param table [Symbol]
        # @param id [String]
        # @return [Hash{Symbol => Object}, nil]
        sig { override.params(table: Symbol, id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def read_row(table:, id:)
          rows_for(table)[id]&.dup
        end

        private

        # The rows of a table, creating the bucket on first use.
        #
        # @param table [Symbol]
        # @return [Hash{String => Hash{Symbol => Object}}]
        sig { params(table: Symbol).returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def rows_for(table)
          rows = @tables[table]
          return rows unless rows.nil?

          @tables[table] = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
          T.must(@tables[table])
        end

        # The primary key column of a table, so rows can be keyed by it.
        #
        # @param table [Symbol]
        # @return [Symbol]
        sig { params(table: Symbol).returns(Symbol) }
        def primary_key(table)
          PRIMARY_KEYS.fetch(table)
        end
      end
    end
  end
end
