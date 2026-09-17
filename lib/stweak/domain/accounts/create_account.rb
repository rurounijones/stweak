# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../command'
require_relative 'account_id'
require_relative 'display_name'
require_relative 'email'
require_relative 'password_plain_text'
require_relative 'username'

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

        sig { returns(Username) }
        attr_reader :username

        sig { returns(PasswordPlainText) }
        attr_reader :password

        sig { returns(DisplayName) }
        attr_reader :name

        sig { returns(Email) }
        attr_reader :email

        # @param account_id [AccountId] the account to create
        # @param username [Username]
        # @param password [PasswordPlainText] the raw password, hashed before
        #   storage
        # @param name [DisplayName]
        # @param email [Email]
        # rubocop:disable Lint/MissingSuper -- Command defines no initialize for this to call
        sig do
          params(account_id: AccountId, username: Username, password: PasswordPlainText,
                 name: DisplayName, email: Email).void
        end
        def initialize(account_id:, username:, password:, name:, email:)
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
