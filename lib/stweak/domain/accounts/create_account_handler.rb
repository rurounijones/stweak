# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'account'
require_relative 'create_account'
require_relative '../security/password_hasher'
require_relative '../../ports/checkpoint_store'
require_relative '../../ports/event_store'

module Stweak
  module Domain
    module Accounts
      # An application service: hashes the command's password, drives the
      # Account aggregate, and appends the resulting event to the event store,
      # persisting a checkpoint after the append when the aggregate reports one
      # due. The command validated itself when it was built. Driving adapters
      # call this; it is deliberately built to be driven more than one way
      # without any change to the domain.
      #
      # Checkpointing is the aggregate's implementation detail: the handler
      # passes a stored checkpoint into replay and persists whatever checkpoint
      # the aggregate produces, and cannot tell whether a replay used one.
      class CreateAccountHandler
        extend T::Sig

        # @param event_store [Stweak::Ports::EventStore]
        # @param password_hasher [Stweak::Domain::Security::PasswordHasher]
        # @param checkpoint_store [Stweak::Ports::CheckpointStore]
        sig do
          params(
            event_store: Stweak::Ports::EventStore,
            password_hasher: Stweak::Domain::Security::PasswordHasher,
            checkpoint_store: Stweak::Ports::CheckpointStore
          ).void
        end
        def initialize(event_store:, password_hasher:, checkpoint_store:)
          @event_store = event_store
          @password_hasher = password_hasher
          @checkpoint_store = checkpoint_store
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

        # Rebuild the account from its stream, restoring from a stored
        # checkpoint if one exists and applying only the events after it. When
        # a checkpoint is present, only the tail after its version is read from
        # the store, so the checkpoint saves the read as well as the replay.
        # The handler cannot tell whether a checkpoint was used: replay presents
        # the same account either way.
        #
        # @param account_id [AccountId]
        # @return [Account]
        sig { params(account_id: AccountId).returns(Account) }
        def load_account(account_id)
          checkpoint = @checkpoint_store.get(owner_type: Account, owner_id: account_id)
          after = checkpoint.nil? ? 0 : checkpoint.version
          Account.replay(
            id: account_id,
            events: @event_store.read_stream(owner_type: Account, stream_id: account_id, after: after),
            checkpoint: checkpoint
          )
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

        # Append an account's uncommitted events at its expected version, then
        # persist the checkpoint the account reports, if any. The checkpoint is
        # written only after the append succeeds, so it never covers events
        # that did not commit.
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
          persist_checkpoint(account)
        end

        # Store the account's checkpoint, if one is due. Whether one is due is
        # the aggregate's decision; the handler merely persists it.
        #
        # @param account [Account]
        sig { params(account: Account).void }
        def persist_checkpoint(account)
          checkpoint = account.checkpoint
          return if checkpoint.nil?

          @checkpoint_store.put(owner_type: Account, owner_id: account.id, checkpoint: checkpoint)
        end
      end
    end
  end
end
