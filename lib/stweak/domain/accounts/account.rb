# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../aggregate'
require_relative '../error'
require_relative '../value_missing'
require_relative 'account_created'

module Stweak
  module Domain
    # Accounts: the aggregate, its events and its commands.
    module Accounts
      # Raised when an Account that already exists is created again, whether
      # that is known from the account's own state or from a concurrent write
      # to the event store. A conflict, in the domain taxonomy: the change
      # clashes with the account already existing.
      class AccountAlreadyExists < ConflictError; end

      # The Account aggregate. Guards the rules around creating an account, and
      # derives its state by replaying its own stream rather than from a stored
      # record.
      class Account < Aggregate
        extend T::Sig

        # An account's id is an AccountId, narrowed from the base Aggregate's
        # Id. The account is always constructed with an AccountId, so the cast
        # records a fact rather than asserting one.
        #
        # @return [AccountId]
        sig { override.returns(AccountId) }
        def id
          T.cast(super, AccountId)
        end

        # Whether an AccountCreated event has been applied.
        sig { returns(T::Boolean) }
        attr_reader :created

        sig { returns(String) }
        attr_reader :username

        sig { returns(String) }
        attr_reader :password_hash

        sig { returns(T.any(String, T.class_of(ValueMissing))) }
        attr_reader :name

        sig { returns(T.any(String, T.class_of(ValueMissing))) }
        attr_reader :email

        # @param id [AccountId] the account id, also its stream id
        sig { params(id: AccountId).void }
        def initialize(id:)
          super
          @created = T.let(false, T::Boolean)
          @username = T.let('', String)
          @password_hash = T.let('', String)
          # Declared untyped rather than the precise union type: a `T.let` type
          # annotation has no runtime behaviour for mutation testing to pin.
          # The readers above expose the precise type.
          @name = T.let('', T.untyped)
          @email = T.let('', T.untyped)
        end

        # Create the account, emitting an AccountCreated event. The password
        # arriving here is already a hash.
        #
        # @param username [String]
        # @param password_hash [String]
        # @param name [String]
        # @param email [String]
        # @param occurred_at [Time]
        # @raise [AccountAlreadyExists] if the account has already been created
        sig do
          params(username: String, password_hash: String, name: String, email: String, occurred_at: Time).void
        end
        def create(username:, password_hash:, name:, email:, occurred_at:)
          raise AccountAlreadyExists, "account #{id} already exists" if created

          record(
            AccountCreated.new(
              stream_id: id, sequence: expected_version + 1, occurred_at: occurred_at,
              account_id: id, username: username, password_hash: password_hash, name: name, email: email
            )
          )
        end

        # @param event [Event]
        sig { override.params(event: Event).void }
        def apply(event)
          case event
          when AccountCreated
            @created = true
            @username = event.username
            @password_hash = event.password_hash
            @name = event.name
            @email = event.email
          else
            # A stream containing an event this aggregate does not know is a
            # corrupt-stream or history-mismatch bug, not a condition a caller
            # is expected to handle, so this stays ArgumentError rather than
            # joining the domain taxonomy.
            raise ArgumentError, "account #{id} does not know event #{event.class}"
          end
        end

        # The account's state, serialized to a plain hash for a checkpoint.
        # The display name and the email are personal data, so a durable
        # checkpoint store must encrypt them — the same crypto-shredding
        # boundary as the event store.
        #
        # @return [Hash{String => Object}]
        sig { override.returns(T::Hash[String, T.untyped]) }
        def checkpoint_state
          {
            'created' => @created, 'username' => @username, 'password_hash' => @password_hash,
            'name' => @name, 'email' => @email
          }
        end

        # The display name and the email are the account's personal data, so a
        # durable checkpoint store must encrypt them — the crypto-shredding
        # boundary named on checkpoint_state above.
        #
        # @return [Array<Symbol>]
        sig { override.returns(T::Array[Symbol]) }
        def self.checkpoint_pii_fields
          %i[name email]
        end

        # Hydrate the account's state from a checkpoint, so that replaying only
        # the events after the checkpoint gives the same account as replaying
        # the whole stream.
        #
        # @param state [Hash{String => Object}] the serialized state from a
        #   checkpoint
        sig { override.params(state: T::Hash[String, T.untyped]).void }
        def restore(state)
          @created = state.fetch('created')
          @username = state.fetch('username')
          @password_hash = state.fetch('password_hash')
          @name = state.fetch('name')
          @email = state.fetch('email')
        end
      end
    end
  end
end
