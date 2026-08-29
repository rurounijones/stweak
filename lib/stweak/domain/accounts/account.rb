# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../aggregate'
require_relative '../error'
require_relative '../value_missing'
require_relative 'account_created'
require_relative 'display_name'
require_relative 'email'
require_relative 'username'

module Stweak
  module Domain
    # Accounts: the aggregate, its events and its commands.
    module Accounts
      # Raised when an Account that already exists is created again, whether
      # that is known from the account's own state or from a concurrent write
      # to the event store. A conflict, in the domain taxonomy: the change
      # clashes with the account already existing.
      class AccountAlreadyExists < ConflictError; end

      # Raised when an account is created with a username another account
      # already uses. A conflict, in the domain taxonomy: the change clashes
      # with an existing username. The rule spans aggregates — no single
      # account can know the others' usernames — so it is checked at handling
      # time against the read model of usernames, not by the aggregate.
      class UsernameTaken < ConflictError; end

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

        sig { returns(T.any(Username, T.class_of(ValueMissing))) }
        attr_reader :username

        sig { returns(String) }
        attr_reader :password_hash

        sig { returns(T.any(DisplayName, T.class_of(ValueMissing))) }
        attr_reader :name

        sig { returns(T.any(Email, T.class_of(ValueMissing))) }
        attr_reader :email

        # @param id [AccountId] the account id, also its stream id
        sig { params(id: AccountId).void }
        def initialize(id:)
          super
          @created = T.let(false, T::Boolean)
          @password_hash = T.let('', String)
          # An account that has not been created yet has no username, name or
          # email. The absence is ValueMissing rather than nil or an empty
          # string: an observable, non-nil sentinel that a mutation cannot
          # quietly stand in for, and the same marker a shredded field reads as.
          # Declared untyped rather than the precise union type: a `T.let` type
          # annotation has no runtime behaviour for mutation testing to pin.
          # The readers above expose the precise type.
          @username = T.let(ValueMissing, T.untyped)
          @name = T.let(ValueMissing, T.untyped)
          @email = T.let(ValueMissing, T.untyped)
        end

        # Create the account, emitting an AccountCreated event. The password
        # arriving here is already a hash.
        #
        # @param username [Username]
        # @param password_hash [String]
        # @param name [DisplayName]
        # @param email [Email]
        # @param occurred_at [Time]
        # @raise [AccountAlreadyExists] if the account has already been created
        sig do
          params(username: Username, password_hash: String, name: DisplayName, email: Email, occurred_at: Time).void
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
            'created' => @created, 'username' => @username.to_s, 'password_hash' => @password_hash,
            'name' => @name.to_stored, 'email' => @email.to_stored
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
          name = state.fetch('name')
          email = state.fetch('email')
          @created = state.fetch('created')
          @username = Username.new(value: state.fetch('username'))
          @password_hash = state.fetch('password_hash')
          @name = wrap_pii(name) { |string| DisplayName.new(value: string) }
          @email = wrap_pii(email) { |string| Email.new(value: string) }
        end

        private

        # Re-wrap a restored PII field. A serialized value is a string, which the
        # block turns into its value object; the ValueMissing marker of a
        # shredded field is not a string and passes through unchanged. The type
        # test is what tells the two apart — the marker is the only non-string a
        # restored field can hold.
        #
        # @param value [Object] the serialized field: a string or the marker
        # @yieldparam string [String] the serialized value, when it is a string
        # @yieldreturn [Object] the value object built from it
        # @return [Object] the value object, or the marker unchanged
        #
        # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
        # anonymous `&`; the named block parameter is required to match the sig.
        sig do
          params(value: T.untyped, blk: T.proc.params(arg0: String).returns(T.untyped)).returns(T.untyped)
        end
        def wrap_pii(value, &blk)
          case value
          when String then yield(value)
          else value
          end
        end
        # rubocop:enable Naming/BlockForwarding
      end
    end
  end
end
