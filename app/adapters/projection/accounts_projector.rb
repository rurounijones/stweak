# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # Projectors: application-layer handlers that translate domain events into
    # create/update/delete operations on the read models they maintain.
    module Projection
      # The accounts projector.
      class AccountsProjector < Stweak::Domain::Projection
        extend T::Sig

        # @param store [Stweak::Ports::ProjectionStore] the relational store
        sig { params(store: Stweak::Ports::ProjectionStore).void }
        def initialize(store:)
          @store = store
        end

        # Fold one plaintext event into the accounts table.
        #
        # @param event [Stweak::Domain::Event]
        sig { override.params(event: Stweak::Domain::Event).void }
        def apply(event)
          case event
          when Stweak::Domain::Accounts::AccountCreated
            @store.upsert(table: :accounts, attributes: account_attributes(event))
          end
        end

        # Fold an event whose PII fields are already encrypted into the accounts
        # table. The projection store receives ciphertext directly and therefore
        # does not need to load the account's encryption key.
        #
        # @param event [Stweak::Domain::Event]
        sig { params(event: Stweak::Domain::Event).void }
        def apply_encrypted(event)
          case event
          when Stweak::Domain::Accounts::AccountCreated
            @store.upsert(table: :accounts, attributes: encrypted_account_attributes(event))
          end
        end

        # @return [Boolean]
        sig { returns(T::Boolean) }
        def supports_encrypted_events?
          true
        end

        # Return the accounts table to the empty state.
        sig { override.void }
        def reset
          @store.clear(table: :accounts)
        end

        private

        # @param event [Stweak::Domain::Accounts::AccountCreated]
        # @return [Hash{Symbol => Object}]
        sig do
          params(event: Stweak::Domain::Accounts::AccountCreated)
            .returns(T::Hash[Symbol, T.untyped])
        end
        def account_attributes(event)
          {
            account_id: event.account_id.to_s,
            username: event.username,
            password_hash: event.password_hash,
            name: event.name,
            email: event.email,
            created_at: event.created_at.iso8601
          }
        end

        # @param event [Stweak::Domain::Accounts::AccountCreated]
        # @return [Hash{Symbol => Object}]
        sig do
          params(event: Stweak::Domain::Accounts::AccountCreated)
            .returns(T::Hash[Symbol, T.untyped])
        end
        def encrypted_account_attributes(event)
          {
            account_id: event.account_id.to_s,
            username: event.username,
            password_hash: event.password_hash,
            name_cipher: event.name,
            email_cipher: event.email,
            created_at: event.created_at.iso8601
          }
        end
      end
    end
  end
end
