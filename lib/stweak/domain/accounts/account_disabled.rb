# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../event'
require_relative 'account_id'

module Stweak
  module Domain
    module Accounts
      # The event that records an account being disabled. A disabled account
      # keeps its data but cannot authenticate.
      class AccountDisabled < Event
        # The schema version of this event. See "Event versioning" in the
        # design decisions.
        VERSION = 1

        # The name this event is known by in the log. Declared rather than
        # derived from the class name. See "The event type name is declared,
        # not derived" in the design decisions.
        TYPE = 'AccountDisabled'

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

        # Rebuild from the serialized form.
        #
        # @param hash [Hash{String => Object}]
        # @return [AccountDisabled]
        sig { override.params(hash: T::Hash[String, T.untyped]).returns(AccountDisabled) }
        def self.from_h(hash)
          new(
            stream_id: AccountId.new(value: hash.fetch('stream_id')),
            sequence: hash.fetch('sequence'), occurred_at: Time.iso8601(hash.fetch('occurred_at')),
            created_at: Time.iso8601(hash.fetch('created_at'))
          )
        end
      end
    end
  end
end
