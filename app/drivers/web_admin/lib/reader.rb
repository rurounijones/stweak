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

    # Authenticate an account against the projected accounts table. The raw
    # username arrives as a form string; it is wrapped in the domain's value
    # object here, at the app boundary. A username the Username rule refuses is
    # rejected as a failed login rather than built into a value object the
    # domain would refuse — the login form's acceptance policy, which is the
    # app's to make.
    sig { params(username: String, password: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def authenticate(username:, password:)
      name = parse_username(username)
      return unless name

      @authenticator.call(username: name, password: password)
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

    private

    # A form username as a Username, or nil when the Username rule refuses it.
    sig { params(username: String).returns(T.nilable(Stweak::Domain::Accounts::Username)) }
    def parse_username(username)
      Stweak::Domain::Accounts::Username.new(value: username)
    rescue Stweak::Domain::ValidationError
      nil
    end
  end
end
