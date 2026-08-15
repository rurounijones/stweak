# typed: false
# frozen_string_literal: true

# Coverage is measured unless something opts out, mirroring the other bundles.
# This driver loads code from the domain gem and the shared app/adapters area,
# so coverage is filtered down to only this driver's own lib — the domain and
# the adapters each have their own suites and their own gates.
unless ENV['SKIP_COVERAGE']
  require 'simplecov'
  require 'simplecov-lcov'

  SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::LcovFormatter]
  )

  driver_lib = File.expand_path('../lib', __dir__)
  SimpleCov.start do
    enable_coverage :branch

    add_filter { |source| !source.filename.start_with?(driver_lib) }

    minimum_coverage line: 100, branch: 100
  end
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
