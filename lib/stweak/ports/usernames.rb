# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/accounts/username'

module Stweak
  module Ports
    # The port a read of "which usernames are in use" implements: the check the
    # write side makes before creating an account, so a username cannot be taken
    # twice. The rule spans aggregates, so no single aggregate can enforce it
    # itself; it is answered by a read of the accounts table, which the
    # projection system keeps current with the event log. Only the username is
    # consulted — a non-PII field — so the check survives the crypto-shredding
    # of an account's personal data.
    module Usernames
      extend T::Sig
      extend T::Helpers

      interface!

      # Whether a username is already in use.
      #
      # @param username [Stweak::Domain::Accounts::Username]
      # @return [Boolean]
      sig { abstract.params(username: Stweak::Domain::Accounts::Username).returns(T::Boolean) }
      def include?(username); end
    end
  end
end
