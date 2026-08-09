# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account_handler'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../support/property/domain_generators'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
# Builds a CreateAccount command, defaulting every field except the id.
def build_create_account_command(account_id:, username: 'alice', password: 'hunter2', name: 'Alice',
                                 email: 'alice@example.com')
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: account_id,
    username: username,
    password: password,
    name: name,
    email: email
  )
end

# The state an account exposes, for comparing a handled account with a
# replayed one.
def account_state(account)
  [account.created, account.username, account.name, account.password_hash]
end

def replay_account(account, store)
  events = store.read_stream(owner_type: Stweak::Domain::Accounts::Account, stream_id: account.id)
  Stweak::Domain::Accounts::Account.replay(id: account.id, events: events)
end

RSpec.describe Stweak::Domain::Accounts::CreateAccountHandler do
  include DomainPropertyGenerators

  subject(:handler) do
    described_class.new(event_store: store, password_hasher: password_hasher)
  end

  let(:store) do
    Stweak::Adapters::EventStore::EncryptingEventStore.new(
      store: Stweak::Adapters::EventStore::InMemoryEventStore.new,
      cipher: Stweak::Adapters::Encryption::AesGcm.new,
      key_store: Stweak::Adapters::KeyStore::InMemoryKeyStore.new
    )
  end
  let(:password_hasher) { Stweak::Adapters::Security::Pbkdf2PasswordHasher.new(iterations: 1_000) }
  let(:owner_type) { Stweak::Domain::Accounts::Account }
  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }

  it 'creates the account' do
    account = handler.handle(build_create_account_command(account_id: account_id))
    expect(account.created).to be(true)
  end

  it 'appends the AccountCreated event' do
    handler.handle(build_create_account_command(account_id: account_id))
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id).length).to eq(1)
  end

  it 'stores the username in the event' do
    handler.handle(build_create_account_command(account_id: account_id))
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id).first.username).to eq('alice')
  end

  it 'stores the plaintext name in the event' do
    handler.handle(build_create_account_command(account_id: account_id))
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id).first.name).to eq('Alice')
  end

  it 'stores a digest of the password' do
    account = handler.handle(build_create_account_command(account_id: account_id))
    expect(account.password_hash).to start_with('pbkdf2-sha256$')
  end

  it 'never stores the raw password' do
    account = handler.handle(build_create_account_command(account_id: account_id))
    expect(account.password_hash).not_to eq('hunter2')
  end

  it 'stores the same digest in the event' do
    account = handler.handle(build_create_account_command(account_id: account_id))
    event = store.read_stream(owner_type: owner_type, stream_id: account_id).first
    expect(event.password_hash).to eq(account.password_hash)
  end

  it 'rejects creating the same account twice' do
    handler.handle(build_create_account_command(account_id: account_id))
    expect { handler.handle(build_create_account_command(account_id: account_id, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'surfaces a concurrent append as AccountAlreadyExists' do
    store = Stweak::Adapters::EventStore::InMemoryEventStore.new
    allow(store).to receive(:append).and_raise(Stweak::Ports::ConcurrencyError)
    handler = described_class.new(event_store: store, password_hasher: password_hasher)
    expect { handler.handle(build_create_account_command(account_id: account_id)) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'writes events that replay to the account it returned', :property do
    PropCheck.forall(create_account_command) do |command|
      handled = handler.handle(command)
      expect(account_state(replay_account(handled, store))).to eq(account_state(handled))
    end
  end
end
