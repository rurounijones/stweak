# typed: false
# frozen_string_literal: true

require 'stweak'

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.order = :random
  Kernel.srand config.seed
end
