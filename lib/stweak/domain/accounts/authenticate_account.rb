# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../security/password_hasher'
require_relative '../../ports/projection_store'

module Stweak
  module Domain
    module Accounts
      # Authenticates an account against its projected read model. A missing
      # username and an incorrect password return the same nil result, so a
      # caller cannot distinguish those cases from this service.
      class AuthenticateAccount
        extend T::Sig

        # @param projection_store [Stweak::Ports::ProjectionStore]
        # @param password_hasher [Stweak::Domain::Security::PasswordHasher]
        sig do
          params(
            projection_store: Stweak::Ports::ProjectionStore,
            password_hasher: Stweak::Domain::Security::PasswordHasher
          ).void
        end
        def initialize(projection_store:, password_hasher:)
          @projection_store = projection_store
          @password_hasher = password_hasher
        end

        # Authenticate with a username and raw password.
        #
        # @param username [String]
        # @param password [String]
        # @return [Hash{Symbol => Object}, nil] the projected account or nil
        sig do
          params(username: String, password: String)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def call(username:, password:)
          account = find_account(username)
          return unless account
          return unless @password_hasher.verify(password: password, digest: account.fetch(:password_hash).to_s)

          account
        end

        private

        sig { params(username: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def find_account(username)
          @projection_store.read_all(table: :accounts).find { |account| account[:username] == username }
        end
      end
    end
  end
end
