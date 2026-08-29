# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'
require_relative '../event'
require_relative '../value_missing'
require_relative 'account_id'
require_relative 'display_name'
require_relative 'email'
require_relative 'username'

module Stweak
  module Domain
    module Accounts
      # The event that records an Account being created: its username, the hash
      # of its password, its display name, and its email. The password hash is
      # stored, the raw password never reaches the log. The display name and the
      # email are personal data and are encrypted at rest. created_at, the time
      # the event was committed, is stamped by the store just before the write.
      class AccountCreated < Event
        # The schema version of this event. See "Event versioning" in the
        # design decisions.
        VERSION = 1

        # The name this event is known by in the log, and the key the durable
        # registry rebuilds it under. Declared rather than derived from the
        # class name, so it is stable across refactors and cannot collide with
        # another aggregate's event under a shared leaf name. See "The event
        # type name is declared, not derived" in the design decisions.
        TYPE = 'AccountCreated'

        sig { returns(AccountId) }
        attr_reader :account_id

        sig { returns(Username) }
        attr_reader :username

        sig { returns(String) }
        attr_reader :password_hash

        sig { returns(T.any(DisplayName, T.class_of(ValueMissing))) }
        attr_reader :name

        sig { returns(T.any(Email, T.class_of(ValueMissing))) }
        attr_reader :email

        # @param stream_id [Id] the account's stream, its id
        # @param sequence [Integer]
        # @param occurred_at [Time]
        # @param account_id [AccountId] the account created
        # @param username [Username]
        # @param password_hash [String]
        # @param name [DisplayName, Stweak::Domain::ValueMissing] the display
        #   name, or ValueMissing if the account's data has been shredded
        # @param email [Email, Stweak::Domain::ValueMissing] the email, or
        #   ValueMissing if the account's data has been shredded
        # @param created_at [Time] when the event was committed, defaulting to
        #   occurred_at until the store stamps the true write time at append
        # @raise [Stweak::Domain::ValidationError] if the sequence is not
        #   positive or the password hash is empty; the value objects validate
        #   their own fields at their construction
        # rubocop:disable Metrics/ParameterLists -- an event constructor carries every field it records
        sig do
          params(
            stream_id: Id,
            sequence: Integer,
            occurred_at: Time,
            account_id: AccountId,
            username: Username,
            password_hash: String,
            name: T.any(DisplayName, T.class_of(ValueMissing)),
            email: T.any(Email, T.class_of(ValueMissing)),
            created_at: Time
          ).void
        end
        def initialize(
          stream_id:,
          sequence:,
          occurred_at:,
          account_id:,
          username:,
          password_hash:,
          name:,
          email:,
          created_at: occurred_at
        )
          super(stream_id: stream_id, sequence: sequence, occurred_at: occurred_at, created_at: created_at)
          raise ValidationError, 'password hash must not be empty' if password_hash.empty?

          @account_id = account_id
          @username = username
          @password_hash = password_hash
          @name = name
          @email = email
        end
        # rubocop:enable Metrics/ParameterLists

        # @return [String] the event's type name
        sig { override.returns(String) }
        def type
          TYPE
        end

        # @return [Integer] the schema version
        sig { override.returns(Integer) }
        def version
          VERSION
        end

        # The display name and the email are the account's personal data.
        #
        # @return [Array<Symbol>]
        sig { override.returns(T::Array[Symbol]) }
        def self.pii_fields
          %i[name email]
        end

        # The value objects collapse to their strings here, so the serialized
        # form the store and the crypto boundary see is plain data. A shredded
        # name or email is ValueMissing rather than a value object; to_stored
        # passes the marker through unchanged and the value objects yield their
        # string, so neither needs a type check here.
        sig { override.returns(T::Hash[String, T.untyped]) }
        def to_h
          super.merge(
            'account_id' => account_id.to_s,
            'username' => username.to_s,
            'password_hash' => password_hash,
            'name' => name.to_stored,
            'email' => email.to_stored
          )
        end

        # Rebuild from the serialized form, re-wrapping each string field in its
        # value object. A name or email that is ValueMissing — the store's
        # marker for a shredded field — is passed through as-is rather than
        # wrapped, since there is no value to wrap.
        #
        # @param hash [Hash{String => Object}]
        # @return [AccountCreated]
        sig { override.params(hash: T::Hash[String, T.untyped]).returns(AccountCreated) }
        def self.from_h(hash)
          new(
            stream_id: AccountId.new(value: hash.fetch('stream_id')), sequence: hash.fetch('sequence'),
            occurred_at: Time.iso8601(hash.fetch('occurred_at')), created_at: Time.iso8601(hash.fetch('created_at')),
            account_id: AccountId.new(value: hash.fetch('account_id')),
            username: Username.new(value: hash.fetch('username')), password_hash: hash.fetch('password_hash'),
            name: display_name_from(hash.fetch('name')), email: email_from(hash.fetch('email'))
          )
        end

        # Re-wrap a serialized display name: a string becomes a DisplayName, the
        # ValueMissing marker of a shredded field passes through unchanged. The
        # string-like test (`to_str`) is what tells the two apart — a real value
        # is a String, the marker is not — rather than a class check, which no
        # test could pin down while the marker is the only non-String it sees.
        sig do
          params(value: T.any(String, T.class_of(ValueMissing)))
            .returns(T.any(DisplayName, T.class_of(ValueMissing)))
        end
        private_class_method def self.display_name_from(value)
          case value
          when String then DisplayName.new(value: value)
          else value
          end
        end

        # Re-wrap a serialized email: a string becomes an Email, the ValueMissing
        # marker of a shredded field passes through unchanged. See
        # {display_name_from} for why the check is string-likeness, not class.
        sig do
          params(value: T.any(String, T.class_of(ValueMissing)))
            .returns(T.any(Email, T.class_of(ValueMissing)))
        end
        private_class_method def self.email_from(value)
          case value
          when String then Email.new(value: value)
          else value
          end
        end
      end
    end
  end
end
