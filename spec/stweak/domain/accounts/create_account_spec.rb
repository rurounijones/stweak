# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../support/property/generators'

# Concise builders for the account value objects, to keep examples short.
def make_username(value) = Stweak::Domain::Accounts::Username.new(value: value)
def make_display_name(value) = Stweak::Domain::Accounts::DisplayName.new(value: value)
def make_email(value) = Stweak::Domain::Accounts::Email.new(value: value)

# A CreateAccount command from raw strings, wrapping each field in its value
# object. Defaults to Alice's, so an example overrides only what it cares about.
def build_command(account_id:, username: 'alice', password: 'hunter2', name: 'Alice', email: 'alice@example.com')
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: Stweak::Domain::Accounts::AccountId.new(value: account_id), username: make_username(username),
    password: password, name: make_display_name(name), email: make_email(email)
  )
end

# A command must either be rejected at construction — its own empty-password
# guard, or a value object rejecting an empty field — or hold its inputs
# faithfully; the example tests pin which fields are which.
def expect_construction_contract(account_id, username, password, name, email)
  command = build_command(account_id: account_id, username: username, password: password, name: name, email: email)
  expect([command.account_id.to_s, command.username.to_s, command.password, command.name.pii, command.email.pii])
    .to eq([account_id, username, password, name, email])
rescue Stweak::Domain::ValidationError
  nil
end

RSpec.describe Stweak::Domain::Accounts::CreateAccount do
  include PropertyGenerators

  subject(:command) { build_command(account_id: account_id_value) }

  let(:account_id_value) { '00000000-0000-4000-8000-000000000001' }

  it 'holds the account id' do
    expect(command.account_id).to eq(Stweak::Domain::Accounts::AccountId.new(value: account_id_value))
  end

  it 'holds the username' do
    expect(command.username).to eq(make_username('alice'))
  end

  it 'holds the password' do
    expect(command.password).to eq('hunter2')
  end

  it 'holds the name' do
    expect(command.name).to eq(make_display_name('Alice'))
  end

  it 'holds the email' do
    expect(command.email).to eq(make_email('alice@example.com'))
  end

  it 'rejects an empty password' do
    expect { build_command(account_id: account_id_value, password: '') }
      .to raise_error(Stweak::Domain::ValidationError, /password/)
  end

  it 'either rejects a command or holds its inputs faithfully', :property do
    PropCheck.forall(
      one_of(uuid, string), string, string, string, string
    ) do |account_id, username, password, name, email|
      expect_construction_contract(account_id, username, password, name, email)
    end
  end
end
