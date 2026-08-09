# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'
require_relative '../event'
require_relative '../value_missing'
require_relative 'account_id'

module Stweak
  module Domain
    module Accounts
      # The event that records an Account being created: its username, the hash
      # of its password, its display name, and its email. The password hash is
      # stored, the raw password never reaches the log. The display name and the
      # email are personal data and are encrypted at rest. created_at, the time
      # the event was committed, is stamped by the store just before the write.
      class AccountCreated < Event
        # The schema version of this event. See "Event versioning" in
        # README.md.
        VERSION = 1

        sig { returns(AccountId) }
        attr_reader :account_id

        sig { returns(String) }
        attr_reader :username

        sig { returns(String) }
        attr_reader :password_hash

        sig { returns(T.any(String, T.class_of(ValueMissing))) }
        attr_reader :name

        sig { returns(T.any(String, T.class_of(ValueMissing))) }
        attr_reader :email

        # @param stream_id [Id] the account's stream, its id
        # @param sequence [Integer]
        # @param occurred_at [Time]
        # @param account_id [AccountId] the account created
        # @param username [String]
        # @param password_hash [String]
        # @param name [String, Stweak::Domain::ValueMissing] the display name, or
        #   ValueMissing if the account's data has been shredded
        # @param email [String, Stweak::Domain::ValueMissing] the email, or
        #   ValueMissing if the account's data has been shredded
        # @param created_at [Time] when the event was committed, defaulting to
        #   occurred_at until the store stamps the true write time at append
        # @raise [Stweak::Domain::ValidationError] if the sequence is not
        #   positive or a content field is empty
        # rubocop:disable Metrics/ParameterLists -- an event constructor carries every field it records
        sig do
          params(
            stream_id: Id,
            sequence: Integer,
            occurred_at: Time,
            account_id: AccountId,
            username: String,
            password_hash: String,
            name: T.any(String, T.class_of(ValueMissing)),
            email: T.any(String, T.class_of(ValueMissing)),
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
          raise ValidationError, 'username must not be empty' if username.empty?
          raise ValidationError, 'password hash must not be empty' if password_hash.empty?
          # The name and email may be ValueMissing after shredding, so only an
          # empty string is rejected, not a missing value.
          raise ValidationError, 'name must not be empty' if name.is_a?(String) && name.empty?
          raise ValidationError, 'email must not be empty' if email.is_a?(String) && email.empty?

          @account_id = account_id
          @username = username
          @password_hash = password_hash
          @name = name
          @email = email
        end
        # rubocop:enable Metrics/ParameterLists

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

        sig { override.returns(T::Hash[String, T.untyped]) }
        def to_h
          super.merge(
            'account_id' => account_id.to_s,
            'username' => username,
            'password_hash' => password_hash,
            'name' => name,
            'email' => email
          )
        end

        # @param hash [Hash{String => Object}]
        # @return [AccountCreated]
        sig { override.params(hash: T::Hash[String, T.untyped]).returns(AccountCreated) }
        def self.from_h(hash)
          new(
            stream_id: AccountId.new(value: hash.fetch('stream_id')),
            sequence: hash.fetch('sequence'),
            occurred_at: Time.iso8601(hash.fetch('occurred_at')),
            created_at: Time.iso8601(hash.fetch('created_at')),
            account_id: AccountId.new(value: hash.fetch('account_id')),
            username: hash.fetch('username'),
            password_hash: hash.fetch('password_hash'),
            name: hash.fetch('name'), email: hash.fetch('email')
          )
        end
      end
    end
  end
end
