# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../command'
require_relative '../error'
require_relative 'account_id'
require_relative 'display_name'
require_relative 'email'
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

        sig { returns(String) }
        attr_reader :password

        sig { returns(DisplayName) }
        attr_reader :name

        sig { returns(Email) }
        attr_reader :email

        # @param account_id [AccountId] the account to create
        # @param username [Username]
        # @param password [String] the raw password, hashed before storage
        # @param name [DisplayName]
        # @param email [Email]
        # @raise [Stweak::Domain::ValidationError] if the password is empty; the
        #   value objects validate their own fields at their construction
        # rubocop:disable Lint/MissingSuper -- Command defines no initialize for this to call
        sig do
          params(account_id: AccountId, username: Username, password: String, name: DisplayName, email: Email).void
        end
        def initialize(account_id:, username:, password:, name:, email:)
          raise ValidationError, 'password must not be empty' if password.empty?

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
