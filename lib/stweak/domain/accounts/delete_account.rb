# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../command'
require_relative 'account_id'

module Stweak
  module Domain
    module Accounts
      # The command to delete an account and request crypto-shredding of its data.
      class DeleteAccount < Command
        extend T::Sig

        sig { returns(AccountId) }
        attr_reader :account_id

        # @param account_id [AccountId] the account to delete
        # rubocop:disable Lint/MissingSuper -- Command defines no initialize for this to call
        sig { params(account_id: AccountId).void }
        def initialize(account_id:)
          @account_id = account_id
        end
        # rubocop:enable Lint/MissingSuper
      end
    end
  end
end
