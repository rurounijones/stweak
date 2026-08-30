# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'stweak'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative '../../../adapters/projection_store/encrypting'
require_relative '../lib/reader'

RSpec.describe WebAdmin::Reader do
  subject(:reader) do
    described_class.new(
      projection_store: projection_store,
      event_store: event_store,
      password_hasher: password_hasher
    )
  end

  let(:password_hasher) { Stweak::Adapters::Security::Pbkdf2PasswordHasher.new(iterations: 1_000) }

  # One key store shared across both encrypting stores, so an account's event
  # and projection data are encrypted under the same per-account key, as they
  # would be in the running system. The cipher is stateless, so each store
  # constructs its own.
  let(:key_store) { Stweak::Adapters::KeyStore::InMemoryKeyStore.new }

  let(:projection_store) do
    App::Adapters::ProjectionStore::EncryptingProjectionStore.new(
      store: Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new,
      cipher: Stweak::Adapters::Encryption::AesGcm.new, key_store: key_store
    )
  end

  let(:event_store) do
    Stweak::Adapters::EventStore::EncryptingEventStore.new(
      store: Stweak::Adapters::EventStore::InMemoryEventStore.new,
      cipher: Stweak::Adapters::Encryption::AesGcm.new, key_store: key_store, subscription: nil
    )
  end

  # Seed one account into both the projection and the event log, the way the
  # write side would, so the reader has something coherent to read back. A
  # lambda in a let, not a method, so nothing is defined inside a block.
  let(:seed) do
    lambda do |username:, name:, email:, password_hash: 'hash'|
      id = SecureRandom.uuid
      account_id = Stweak::Domain::Accounts::AccountId.new(value: id)
      now = Time.now
      event_store.append(
        owner_type: Stweak::Domain::Accounts::Account,
        stream_id: account_id, expected_version: 0,
        events: [Stweak::Domain::Accounts::AccountCreated.new(
          stream_id: account_id, sequence: 1, occurred_at: now, account_id: account_id,
          username: Stweak::Domain::Accounts::Username.new(value: username), password_hash: password_hash,
          name: Stweak::Domain::Accounts::DisplayName.new(value: name),
          email: Stweak::Domain::Accounts::Email.new(value: email)
        )]
      )
      projection_store.upsert(
        table: :accounts,
        attributes: {
          account_id: id, username: username, password_hash: password_hash,
          name: name, email: email, created_at: now.iso8601
        }
      )
      id
    end
  end

  it 'lists accounts ordered by username' do
    seed.call(username: 'zara', name: 'Zara', email: 'zara@example.com')
    seed.call(username: 'ada', name: 'Ada', email: 'ada@example.com')

    expect(reader.accounts.map { |row| row[:username] }).to eq(%w[ada zara])
  end

  it 'reads one account by id, with personal data decrypted' do
    id = seed.call(username: 'ada', name: 'Ada', email: 'ada@example.com')

    expect(reader.account(id)[:email]).to eq('ada@example.com')
  end

  it 'returns nil for an unknown account id' do
    expect(reader.account('does-not-exist')).to be_nil
  end

  it 'authenticates a projected account' do
    digest = password_hasher.digest(password: 'hunter2')
    seed.call(username: 'ada', name: 'Ada', email: 'ada@example.com', password_hash: digest)

    expect(reader.authenticate(username: 'ada', password: 'hunter2')).to include(username: 'ada')
  end

  it 'rejects an incorrect password' do
    seed.call(username: 'ada', name: 'Ada', email: 'ada@example.com')

    expect(reader.authenticate(username: 'ada', password: 'wrong')).to be_nil
  end

  it 'rejects an unknown username' do
    expect(reader.authenticate(username: 'missing', password: 'hunter2')).to be_nil
  end

  it 'reads the events on an account stream, decrypted' do
    id = seed.call(username: 'ada', name: 'Ada', email: 'ada@example.com')

    expect(reader.events(id).map { |event| event.name.pii }).to eq(['Ada'])
  end
end
