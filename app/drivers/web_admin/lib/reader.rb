# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module WebAdmin
  # The read facade the web app drives: it turns the two read ports — the
  # projection store and the event store — into the three questions the app
  # asks, and nothing more. Keeping this thin and separate from the HTTP layer
  # is what lets it be tested without a web server, and lets the Sinatra routes
  # stay a line each.
  class Reader
    extend T::Sig

    # @param projection_store [Stweak::Ports::ProjectionStore] the read-model
    #   store, decrypting behind its encrypting decorator
    # @param event_store [Stweak::Ports::EventStore] the event log, decrypting
    #   behind its encrypting decorator
    sig do
      params(
        projection_store: Stweak::Ports::ProjectionStore,
        event_store: Stweak::Ports::EventStore
      ).void
    end
    def initialize(projection_store:, event_store:)
      @projection_store = projection_store
      @event_store = event_store
    end

    # Every account in the projection, ordered by username.
    #
    # @return [Array<Hash{Symbol => Object}>]
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def accounts
      @projection_store.read_all(table: :accounts).sort_by { |row| row.fetch(:username).to_s }
    end

    # One account's projected row, or nil if no account has that id. A keyed
    # read of the single row, so showing one account does not scan and decrypt
    # the whole table.
    #
    # @param id [String] the account id
    # @return [Hash{Symbol => Object}, nil]
    sig { params(id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def account(id)
      @projection_store.read_row(table: :accounts, id: id)
    end

    # The events on an account's stream, in sequence order.
    #
    # @param id [String] the account id, which is also its stream id
    # @return [Array<Stweak::Domain::Event>]
    sig { params(id: String).returns(T::Array[Stweak::Domain::Event]) }
    def events(id)
      @event_store.read_stream(
        owner_type: Stweak::Domain::Accounts::Account,
        stream_id: Stweak::Domain::Accounts::AccountId.new(value: id)
      )
    end
  end
end
