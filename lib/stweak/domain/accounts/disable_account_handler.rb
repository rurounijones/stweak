# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'account'
require_relative 'disable_account'
require_relative '../../ports/checkpoint_store'
require_relative '../../ports/event_store'

module Stweak
  module Domain
    module Accounts
      # Handles disabling an account and persists any checkpoint due afterward.
      class DisableAccountHandler
        extend T::Sig

        sig do
          params(event_store: Stweak::Ports::EventStore, checkpoint_store: Stweak::Ports::CheckpointStore).void
        end
        def initialize(event_store:, checkpoint_store:)
          @event_store = event_store
          @checkpoint_store = checkpoint_store
        end

        # @param command [DisableAccount]
        # @return [Account] the disabled account
        sig { params(command: DisableAccount).returns(Account) }
        def handle(command)
          account = load_account(command.account_id)
          account.disable(occurred_at: Time.now)
          append(account)
          account
        rescue Stweak::Ports::ConcurrencyError
          raise AccountAlreadyDisabled
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
