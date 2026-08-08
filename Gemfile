# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Every dependency is `require: false`, without exception. Nothing is loaded
# implicitly; each file requires exactly what it uses, where it uses it. See
# "Explicit requires, no autoloading" in README.md for the reasoning.
group :development, :test do
  gem 'rake', '~> 13.2', require: false
  gem 'rspec', '~> 3.13', require: false
end

group :development do
  gem 'debug', '~> 1.10', require: false
  gem 'redcarpet', '~> 3.6', require: false
  gem 'rubocop', '~> 1.71', require: false
  gem 'rubocop-performance', '~> 1.23', require: false
  gem 'rubocop-rake', '~> 0.6', require: false
  gem 'rubocop-rspec', '~> 3.4', require: false
  gem 'rubocop-sorbet', '~> 0.8', require: false
  gem 'ruby-lsp', '~> 0.23', require: false
  gem 'sorbet', '~> 0.5', require: false
  gem 'tapioca', '~> 0.16', require: false
  gem 'yard', '~> 0.9', require: false
  gem 'yard-junk', '~> 0.0.10', require: false
  gem 'yard-sorbet', '~> 0.9', require: false
end

group :test do
  gem 'mutant-rspec', '~> 0.13', require: false
  gem 'prop_check', '~> 1.0', require: false
  gem 'simplecov', '~> 0.22', require: false
  gem 'simplecov-lcov', '~> 0.8', require: false
end

group :audit do
  gem 'bundler-audit', '~> 0.9', require: false
end
