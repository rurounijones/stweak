# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    module Projection
      # The read of "which usernames are in use", backed by the accounts table:
      # the implementation of Stweak::Ports::Usernames that answers the
      # write-side uniqueness check from the rows the accounts projector has
      # materialized. The username is a non-PII column, so the check reads it
      # directly and survives the crypto-shredding of an account's personal
      # data.
      class Usernames
        include Stweak::Ports::Usernames

        extend T::Sig

        # @param store [Stweak::Ports::ProjectionStore] the store hosting the
        #   accounts table
        sig { params(store: Stweak::Ports::ProjectionStore).void }
        def initialize(store:)
          @store = store
        end

        # @param username [String]
        # @return [Boolean]
        sig { override.params(username: String).returns(T::Boolean) }
        def include?(username)
          @store.read_all(table: :accounts).any? { |row| row[:username] == username }
        end
      end
    end
  end
end
