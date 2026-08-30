# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # Projectors: application-layer handlers that translate domain events into
    # create/update/delete operations on the read models they maintain. They
    # implement Stweak::Domain::Projection so the projection system can drive
    # them — delivering appends, keeping per-stream cursors durable, and
    # clearing the read model on rebuild — while the read-model logic itself
    # lives here in the application layer, not in the domain.
    module Projection
      # The accounts projector: turns the events that concern an account into
      # create/update/delete operations on the accounts table, and ignores the
      # rest, so replaying it over the full log always produces the same table.
      # AccountCreated upserts the account's row; AccountDisabled marks it
      # disabled without removing data, and AccountDeleted removes the row.
      class AccountsProjector < Stweak::Domain::Projection
        extend T::Sig

        # rubocop:disable Lint/MissingSuper -- Projection defines no initialize for this to call
        # @param store [Stweak::Ports::ProjectionStore] the relational store
        #   whose accounts table this projector maintains
        sig { params(store: Stweak::Ports::ProjectionStore).void }
        def initialize(store:)
          @store = store
        end
        # rubocop:enable Lint/MissingSuper

        # Fold one event into the accounts table.
        #
        # @param event [Stweak::Domain::Event]
        sig { override.params(event: Stweak::Domain::Event).void }
        def apply(event)
          case event
          when Stweak::Domain::Accounts::AccountCreated
            @store.upsert(table: :accounts, attributes: account_attributes(event).merge(disabled: false))
          when Stweak::Domain::Accounts::AccountDisabled
            row = @store.read_row(table: :accounts, id: event.stream_id.to_s)
            @store.upsert(table: :accounts, attributes: row.merge(disabled: true)) unless row.nil?
          when Stweak::Domain::Accounts::AccountDeleted
            @store.delete_row(table: :accounts, id: event.stream_id.to_s)
          end
        end

        # Return the accounts table to the empty state, discarding every
        # projected row.
        sig { override.void }
        def reset
          @store.clear(table: :accounts)
        end

        private

        # The account's row as the projector sees it — plaintext name and email
        # included. Encrypting them is the store's boundary: the encrypting
        # decorator turns them into their cipher columns before the row is
        # persisted.
        #
        # @param event [Stweak::Domain::Accounts::AccountCreated]
        # @return [Hash{Symbol => Object}]
        sig do
          params(event: Stweak::Domain::Accounts::AccountCreated)
            .returns(T::Hash[Symbol, T.untyped])
        end
        def account_attributes(event)
          {
            account_id: event.account_id.to_s,
            username: event.username.to_s,
            password_hash: event.password_hash,
            # The value objects collapse to their strings for the row via
            # to_stored; a shredded name or email is ValueMissing, whose
            # to_stored passes the marker through — the form the encrypting
            # projection store expects.
            name: event.name.to_stored,
            email: event.email.to_stored,
            created_at: event.created_at.iso8601
          }
        end
      end
    end
  end
end
