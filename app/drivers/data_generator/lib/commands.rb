# typed: strict
# frozen_string_literal: true

require 'faker'
require 'securerandom'
require 'sorbet-runtime'
require 'stweak'

module DataGenerator
  # The random commands the generators issue, shared by the bounded Generator
  # and the continuous LifecycleGenerator so both drive the domain the same
  # way. Building a plausible create in one place keeps the two callers in
  # step: the same per-process-unique usernames and emails the handler's
  # uniqueness check relies on, the same password shape, and the same
  # value-object wrapping.
  module Commands
    extend T::Sig

    # A plausible create-account command: a fresh id and realistic fields from
    # Faker. The username and email are unique per process, so no two generated
    # accounts collide on the username the handler enforces.
    #
    # @return [Stweak::Domain::Accounts::CreateAccount]
    sig { returns(Stweak::Domain::Accounts::CreateAccount) }
    def self.random_create
      Stweak::Domain::Accounts::CreateAccount.new(
        account_id: Stweak::Domain::Accounts::AccountId.new(value: SecureRandom.uuid),
        username: Stweak::Domain::Accounts::Username.new(value: Faker::Internet.unique.username),
        password: Faker::Internet.password(min_length: 10, max_length: 20),
        name: Stweak::Domain::Accounts::DisplayName.new(value: Faker::Name.name),
        email: Stweak::Domain::Accounts::Email.new(value: Faker::Internet.unique.email)
      )
    end

    # The command to disable an account, continuing the lifecycle a create
    # began.
    #
    # @param account_id [Stweak::Domain::Accounts::AccountId]
    # @return [Stweak::Domain::Accounts::DisableAccount]
    sig do
      params(account_id: Stweak::Domain::Accounts::AccountId)
        .returns(Stweak::Domain::Accounts::DisableAccount)
    end
    def self.disable(account_id)
      Stweak::Domain::Accounts::DisableAccount.new(account_id: account_id)
    end

    # The command to delete an account, ending its lifecycle.
    #
    # @param account_id [Stweak::Domain::Accounts::AccountId]
    # @return [Stweak::Domain::Accounts::DeleteAccount]
    sig do
      params(account_id: Stweak::Domain::Accounts::AccountId)
        .returns(Stweak::Domain::Accounts::DeleteAccount)
    end
    def self.delete(account_id)
      Stweak::Domain::Accounts::DeleteAccount.new(account_id: account_id)
    end
  end
end
