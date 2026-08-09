# typed: false
# frozen_string_literal: true

require 'simplecov'
require 'simplecov-lcov'

SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::LcovFormatter]
)

SimpleCov.start do
  enable_coverage :branch

  add_filter '/spec/'
  # The domain gem has its own suite with its own 100% gate; the app measures
  # only its own code.
  add_filter '/lib/'

  minimum_coverage line: 100, branch: 100
end

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
