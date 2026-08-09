# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account_handler'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/security/password_hasher'
require_relative '../../../../lib/stweak/ports/event_store'
require_relative '../../../support/property/domain_generators'

ACCOUNT_OWNER_TYPE = Stweak::Domain::Accounts::Account
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')

# A run of AccountCreated events at sequences 1..count on one stream, so an
# account can be replayed to any length without an event store behind it.
def account_created_events(account_id, count)
  (1..count).map do |sequence|
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id, sequence: sequence, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5), account_id: account_id,
      username: "user-#{sequence}", password_hash: 'hash', name: "Name #{sequence}",
      email: "user#{sequence}@example.com"
    )
  end
end

# Builds a CreateAccount command, defaulting every field except the id.
def build_create_account_command(account_id:, username: 'alice', password: 'hunter2', name: 'Alice',
                                 email: 'alice@example.com')
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: account_id, username: username, password: password, name: name, email: email
  )
end

# The username is derived from the account id, so commands generated for the
# property can never collide on the username across iterations.
def command_with_unique_username(command)
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: command.account_id, username: "user-#{command.account_id}",
    password: command.password, name: command.name, email: command.email
  )
end

# The state an account exposes, for comparing a handled account with one
# replayed from the events the handler appended.
def account_state(account)
  [account.created, account.username, account.name, account.password_hash]
end

# The events the handler appended for one stream, in append order, drawn from
# the recorded append calls.
def appended_events(appends, stream_id)
  appends.select { |call| call.fetch(:stream_id) == stream_id }.flat_map { |call| call.fetch(:events) }
end

RSpec.describe Stweak::Domain::Accounts::CreateAccountHandler do
  include DomainPropertyGenerators

  subject(:handler) do
    described_class.new(event_store: event_store, password_hasher: password_hasher)
  end

  let(:event_store) { instance_double(Stweak::Ports::EventStore) }
  let(:password_hasher) { instance_double(Stweak::Domain::Security::PasswordHasher) }

  # Every append the handler makes, in order, so its writes can be inspected
  # and — for the property — replayed back into an account.
  let(:appends) { [] }

  before do
    allow(event_store).to receive(:read_stream).and_return([])
    allow(password_hasher).to receive(:digest) { |password:| "digest-of-#{password}" }
    allow(event_store).to receive(:append) { |**call| appends << call }
  end

  it 'creates the account' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.created).to be(true)
  end

  it 'appends one AccountCreated event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).map(&:class)).to eq([Stweak::Domain::Accounts::AccountCreated])
  end

  it 'appends on the account stream at the expected version' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appends.last).to include(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID, expected_version: 0)
  end

  it 'stores the username in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.username).to eq('alice')
  end

  it 'stores the plaintext name in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.name).to eq('Alice')
  end

  it 'hashes the command password through the hasher' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(password_hasher).to have_received(:digest).with(password: 'hunter2')
  end

  it 'stores the digest the hasher produced, never the raw password' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.password_hash).to eq('digest-of-hunter2')
  end

  it 'stores the same digest in the event' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.password_hash).to eq(account.password_hash)
  end

  it 'rejects creating the same account twice' do
    allow(event_store).to receive(:read_stream).and_return(account_created_events(ACCOUNT_ID, 1))
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'surfaces a concurrent append as AccountAlreadyExists' do
    allow(event_store).to receive(:append).and_raise(Stweak::Ports::ConcurrencyError)
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID)) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'writes events that replay to the account it returned', :property do
    PropCheck.forall(create_account_command) do |command|
      handled = handler.handle(command_with_unique_username(command))
      replayed = Stweak::Domain::Accounts::Account.replay(id: handled.id, events: appended_events(appends, handled.id))
      expect(account_state(replayed)).to eq(account_state(handled))
    end
  end
end
