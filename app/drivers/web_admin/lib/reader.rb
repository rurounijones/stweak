# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module WebAdmin
  # The read facade the web app drives: it turns the two read ports — the
  # projection store and the event store — into the questions the app asks.
  class Reader
    extend T::Sig

    sig do
      params(
        projection_store: Stweak::Ports::ProjectionStore,
        event_store: Stweak::Ports::EventStore,
        password_hasher: Stweak::Domain::Security::PasswordHasher
      ).void
    end
    def initialize(projection_store:, event_store:, password_hasher:)
      @projection_store = projection_store
      @event_store = event_store
      @authenticator = Stweak::Domain::Accounts::AuthenticateAccount.new(
        projection_store: projection_store, password_hasher: password_hasher
      )
    end

    # Authenticate an account against the projected accounts table.
    sig { params(username: String, password: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def authenticate(username:, password:)
      @authenticator.call(username: username, password: password)
    end

    # Every account in the projection, ordered by username.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def accounts
      @projection_store.read_all(table: :accounts).sort_by { |row| row.fetch(:username).to_s }
    end

    # One account's projected row, or nil if no account has that id.
    sig { params(id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def account(id)
      @projection_store.read_row(table: :accounts, id: id)
    end

    # The events on an account's stream, in sequence order.
    sig { params(id: String).returns(T::Array[Stweak::Domain::Event]) }
    def events(id)
      @event_store.read_stream(
        owner_type: Stweak::Domain::Accounts::Account,
        stream_id: Stweak::Domain::Accounts::AccountId.new(value: id)
      )
    end
  end
end
