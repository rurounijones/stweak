# typed: false
# frozen_string_literal: true

# Coverage is measured unless something explicitly opts out. Mutant runs the
# suite once per mutation, where a per-run coverage floor would fail
# spuriously and slow every run down, so `rake mutant` sets SKIP_COVERAGE.
unless ENV['SKIP_COVERAGE']
  require 'simplecov'
  require 'simplecov-lcov'

  SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ]
  )

  SimpleCov.start do
    enable_coverage :branch

    add_filter '/spec/'

    minimum_coverage line: 100, branch: 100
  end
end

# Property-based tests are tagged `:property` (see "Property-based testing, as
# research" in README.md). They run in the normal suite, but are excluded under
# mutant, which re-runs the suite once per mutation: generated cases are slower
# than examples, and the example tests cover the same behaviour. Mutant is the
# only context that sets SKIP_COVERAGE, so it doubles as the flag for this.
require_relative '../lib/stweak'
require_relative 'support/sorbet_doubles'
RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.filter_run_excluding :property if ENV['SKIP_COVERAGE']
  config.order = :random
  Kernel.srand config.seed
end
