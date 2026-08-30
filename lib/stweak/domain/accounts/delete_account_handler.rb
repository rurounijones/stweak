# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'account'
require_relative 'delete_account'
require_relative '../../ports/checkpoint_store'
require_relative '../../ports/event_store'

module Stweak
  module Domain
    module Accounts
      # Handles deleting an account. The event store adapter shreds the owner's
      # encryption key after the append; this handler only records the domain fact.
      class DeleteAccountHandler
        extend T::Sig

        sig do
          params(event_store: Stweak::Ports::EventStore, checkpoint_store: Stweak::Ports::CheckpointStore).void
        end
        def initialize(event_store:, checkpoint_store:)
          @event_store = event_store
          @checkpoint_store = checkpoint_store
        end

        # @param command [DeleteAccount]
        # @return [Account] the deleted account
        sig { params(command: DeleteAccount).returns(Account) }
        def handle(command)
          account = load_account(command.account_id)
          account.delete(occurred_at: Time.now)
          append(account)
          account
        rescue Stweak::Ports::ConcurrencyError
          raise AccountAlreadyDeleted
        end

        private

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

        sig { params(account: Account).void }
        def append(account)
          @event_store.append(
            owner_type: Account, stream_id: account.id, expected_version: account.expected_version,
            events: account.uncommitted_events
          )
          checkpoint = account.checkpoint
          return if checkpoint.nil?

          @checkpoint_store.put(owner_type: Account, owner_id: account.id, checkpoint: checkpoint)
        end
      end
    end
  end
end
