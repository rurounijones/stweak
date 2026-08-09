# frozen_string_literal: true

require_relative 'lib/stweak/version'

Gem::Specification.new do |spec|
  spec.name = 'stweak'
  spec.version = Stweak::VERSION
  spec.authors = ['Jeffrey Jones']

  spec.summary = 'Player account management for a theoretical online team PvP game'
  spec.description = <<~DESCRIPTION
    The domain logic for stweak: accounts, the players attached to them, the
    seasons the game is divided into, and the games played within a season.
    Event sourced, hexagonal, and deliberately free of any dependency on the
    technology that stores or drives it.
  DESCRIPTION

  spec.homepage = 'https://github.com/rurounijones/stweak'
  spec.license = 'AGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb', 'sorbet/rbi/shims/**/*.rbi'] +
               %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ['lib']

  # Sorbet signatures are evaluated at load time, so the runtime is a genuine
  # dependency of the shipped gem rather than a development tool.
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  # The encryption and hashing adapters require base64, which Ruby 4.0 ships as
  # a bundled gem: installed with Ruby but not available under Bundler unless
  # declared. A consumer of the adapters needs it, so it is a real dependency.
  spec.add_dependency 'base64', '~> 0.3'
end
