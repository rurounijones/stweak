# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../command'
require_relative '../error'
require_relative 'account_id'

module Stweak
  module Domain
    module Accounts
      # The command to create an Account. Carries the raw password, which the
      # handler hashes before anything reaches the event log; the command itself
      # is never stored. It validates its fields at construction, so an invalid
      # command cannot be built.
      class CreateAccount < Command
        extend T::Sig

        sig { returns(AccountId) }
        attr_reader :account_id

        sig { returns(String) }
        attr_reader :username

        sig { returns(String) }
        attr_reader :password

        sig { returns(String) }
        attr_reader :name

        sig { returns(String) }
        attr_reader :email

        # @param account_id [AccountId] the account to create
        # @param username [String]
        # @param password [String] the raw password, hashed before storage
        # @param name [String]
        # @param email [String]
        # @raise [Stweak::Domain::ValidationError] if a field is empty
        # rubocop:disable Lint/MissingSuper -- Command defines no initialize for this to call
        sig do
          params(account_id: AccountId, username: String, password: String, name: String, email: String).void
        end
        def initialize(account_id:, username:, password:, name:, email:)
          raise ValidationError, 'username must not be empty' if username.empty?
          raise ValidationError, 'password must not be empty' if password.empty?
          raise ValidationError, 'name must not be empty' if name.empty?
          raise ValidationError, 'email must not be empty' if email.empty?

          @account_id = account_id
          @username = username
          @password = password
          @name = name
          @email = email
        end
        # rubocop:enable Lint/MissingSuper
      end
    end
  end
end
