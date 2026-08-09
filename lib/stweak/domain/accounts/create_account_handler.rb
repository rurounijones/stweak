# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'account'
require_relative 'create_account'
require_relative '../security/password_hasher'
require_relative '../../ports/event_store'

module Stweak
  module Domain
    module Accounts
      # An application service: hashes the command's password, drives the
      # Account aggregate, and appends the resulting event to the event store.
      # The command validated itself when it was built. Driving adapters call
      # this; it is deliberately built to be driven more than one way without
      # any change to the domain.
      class CreateAccountHandler
        extend T::Sig

        # @param event_store [Stweak::Ports::EventStore]
        # @param password_hasher [Stweak::Domain::Security::PasswordHasher]
        sig do
          params(
            event_store: Stweak::Ports::EventStore,
            password_hasher: Stweak::Domain::Security::PasswordHasher
          ).void
        end
        def initialize(event_store:, password_hasher:)
          @event_store = event_store
          @password_hasher = password_hasher
        end

        # Handle the command: hash, create, append.
        #
        # @param command [CreateAccount]
        # @return [Account] the created account
        # @raise [AccountAlreadyExists] if the account already exists, whether
        #   known from its state or from a concurrent write
        sig { params(command: CreateAccount).returns(Account) }
        def handle(command)
          account = load_account(command.account_id)
          create_account(account, command)
          append(account)
          account
        rescue Stweak::Ports::ConcurrencyError
          raise AccountAlreadyExists
        end

        private

        # Rebuild the account from its stream.
        #
        # @param account_id [AccountId]
        # @return [Account]
        sig { params(account_id: AccountId).returns(Account) }
        def load_account(account_id)
          Account.replay(id: account_id, events: @event_store.read_stream(owner_type: Account, stream_id: account_id))
        end

        # Hash the command's password and create the account on it.
        #
        # @param account [Account]
        # @param command [CreateAccount]
        # @raise [AccountAlreadyExists] if the account already exists
        sig { params(account: Account, command: CreateAccount).void }
        def create_account(account, command)
          password_hash = @password_hasher.digest(password: command.password)
          account.create(
            username: command.username, password_hash: password_hash,
            name: command.name, email: command.email, occurred_at: Time.now
          )
        end

        # Append an account's uncommitted events at its expected version.
        #
        # @param account [Account]
        # @raise [Stweak::Ports::ConcurrencyError] if the stream has moved on
        sig { params(account: Account).void }
        def append(account)
          @event_store.append(
            owner_type: Account,
            stream_id: account.id,
            expected_version: account.expected_version,
            events: account.uncommitted_events
          )
        end
      end
    end
  end
end
