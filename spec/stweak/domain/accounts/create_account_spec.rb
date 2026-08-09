# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../support/property/generators'

# A command must either be rejected at construction or hold its inputs
# faithfully; the example tests pin which fields are which.
def expect_construction_contract(account_id, username, password, name, email)
  command = Stweak::Domain::Accounts::CreateAccount.new(
    account_id: Stweak::Domain::Accounts::AccountId.new(value: account_id),
    username: username, password: password, name: name, email: email
  )
  expect([command.account_id.to_s, command.username, command.password, command.name, command.email])
    .to eq([account_id, username, password, name, email])
rescue Stweak::Domain::ValidationError
  nil
end

RSpec.describe Stweak::Domain::Accounts::CreateAccount do
  include PropertyGenerators

  subject(:command) do
    described_class.new(account_id: account_id, username: 'alice', password: 'hunter2', name: 'Alice',
                        email: 'alice@example.com')
  end

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }

  it 'holds the account id' do
    expect(command.account_id).to eq(account_id)
  end

  it 'holds the username' do
    expect(command.username).to eq('alice')
  end

  it 'holds the password' do
    expect(command.password).to eq('hunter2')
  end

  it 'holds the name' do
    expect(command.name).to eq('Alice')
  end

  it 'holds the email' do
    expect(command.email).to eq('alice@example.com')
  end

  it 'rejects an empty username' do
    expect do
      described_class.new(account_id: account_id, username: '', password: 'hunter2', name: 'Alice',
                          email: 'alice@example.com')
    end.to raise_error(Stweak::Domain::ValidationError, /username/)
  end

  it 'rejects an empty password' do
    expect do
      described_class.new(account_id: account_id, username: 'alice', password: '', name: 'Alice',
                          email: 'alice@example.com')
    end.to raise_error(Stweak::Domain::ValidationError, /password/)
  end

  it 'rejects an empty name' do
    expect do
      described_class.new(account_id: account_id, username: 'alice', password: 'hunter2', name: '',
                          email: 'alice@example.com')
    end.to raise_error(Stweak::Domain::ValidationError, /name/)
  end

  it 'rejects an empty email' do
    expect do
      described_class.new(account_id: account_id, username: 'alice', password: 'hunter2', name: 'Alice',
                          email: '')
    end.to raise_error(Stweak::Domain::ValidationError, /email/)
  end

  it 'either rejects a command or holds its inputs faithfully', :property do
    PropCheck.forall(
      one_of(uuid, string), string, string, string, string
    ) do |account_id, username, password, name, email|
      expect_construction_contract(account_id, username, password, name, email)
    end
  end
end
