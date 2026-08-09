# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../id'

module Stweak
  module Domain
    module Accounts
      # An account identifier: a UUID validated at construction, so an invalid
      # id can never circulate. Account ids are the stream ids the event store
      # keys accounts by, and the type that distinguishes an account's id from
      # any other kind of id.
      class AccountId < Id
      end
    end
  end
end
