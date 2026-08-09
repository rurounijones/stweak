# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'stweak/version'
require_relative 'stweak/domain/error'
require_relative 'stweak/domain/id'
require_relative 'stweak/domain/value_missing'
require_relative 'stweak/domain/event'
require_relative 'stweak/domain/command'
require_relative 'stweak/domain/aggregate'
require_relative 'stweak/domain/accounts/account_id'
require_relative 'stweak/domain/accounts/account_created'
require_relative 'stweak/domain/accounts/account'
require_relative 'stweak/domain/accounts/create_account'
require_relative 'stweak/domain/owner_registry'
require_relative 'stweak/ports/event_store'
require_relative 'stweak/ports/key_store'

# Player account management for a theoretical online team PvP game.
#
# This gem holds the domain logic and nothing else: no event store, no HTTP
# layer, no persistence. Those live behind ports and are supplied by whatever
# drives the domain. See README.md for the architecture and the reasoning
# behind it.
#
# Note that nothing here is autoloaded. Every file requires exactly what it
# uses, so the dependency graph can be read from the source.
module Stweak
  extend T::Sig

  # The version of this gem.
  #
  # @return [String] the semantic version, for example `"0.0.1"`
  sig { returns(String) }
  def self.version
    VERSION
  end
end
