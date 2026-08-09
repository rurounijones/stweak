# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../projection_store/encrypting'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'

ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')

RSpec.describe App::Adapters::ProjectionStore::EncryptingProjectionStore do
  subject(:store) do
    described_class.new(store: raw_store, cipher: cipher, key_store: key_store)
  end

  let(:raw_store) { Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new }
  let(:cipher) { Stweak::Adapters::Encryption::AesGcm.new }
  let(:key_store) { Stweak::Adapters::KeyStore::InMemoryKeyStore.new }

  let(:account) do
    {
      account_id: ACCOUNT_ID.to_s,
      username: 'alice',
      password_hash: 'hash',
      name: 'Alice',
      email: 'alice@example.com',
      created_at: '2026-01-02T03:04:05Z'
    }
  end

  it 'passes cursor writes and reads through' do
    store.write(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
    expect(store.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 1)
  end

  it 'passes cursor deletion through' do
    store.write(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
    store.delete(projection_name: 'AccountsProjector')
    expect(store.read(projection_name: 'AccountsProjector')).to be_nil
  end

  it 'stores the name as ciphertext' do
    store.upsert(table: :accounts, attributes: account)
    expect(raw_store.read_all(table: :accounts).first[:name_cipher]).not_to eq('Alice')
  end

  it 'stores the email as ciphertext' do
    store.upsert(table: :accounts, attributes: account)
    expect(raw_store.read_all(table: :accounts).first[:email_cipher]).not_to eq('alice@example.com')
  end

  it 'does not keep the plaintext columns in the stored row' do
    store.upsert(table: :accounts, attributes: account)
    expect(raw_store.read_all(table: :accounts).first.keys).not_to include(:name, :email)
  end

  it 'round-trips the plaintext on read' do
    store.upsert(table: :accounts, attributes: account)
    row = store.read_all(table: :accounts).first
    expect(row).to include(name: 'Alice', email: 'alice@example.com', username: 'alice', password_hash: 'hash')
  end

  it 'round-trips the plaintext on a keyed read' do
    store.upsert(table: :accounts, attributes: account)
    row = store.read_row(table: :accounts, id: ACCOUNT_ID.to_s)
    expect(row).to include(name: 'Alice', email: 'alice@example.com', username: 'alice', password_hash: 'hash')
  end

  it 'returns nil for a keyed read of an absent row' do
    expect(store.read_row(table: :accounts, id: ACCOUNT_ID.to_s)).to be_nil
  end

  it 'creates a key for the account on first upsert' do
    store.upsert(table: :accounts, attributes: account)
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID).bytesize).to eq(32)
  end

  it 'reuses the account key on a later upsert' do
    store.upsert(table: :accounts, attributes: account)
    first = key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)
    store.upsert(table: :accounts, attributes: account.merge(name: 'Alice Smith'))
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)).to eq(first)
  end

  it 'reads ValueMissing for the PII fields after the key is shredded' do
    store.upsert(table: :accounts, attributes: account)
    key_store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)
    expect(store.read_all(table: :accounts).first).to include(name: Stweak::Domain::ValueMissing,
                                                              email: Stweak::Domain::ValueMissing)
  end

  it 'still reads non-PII fields after the key is shredded' do
    store.upsert(table: :accounts, attributes: account)
    key_store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)
    expect(store.read_all(table: :accounts).first).to include(username: 'alice', password_hash: 'hash')
  end

  it 'mints a key when some fields are still present' do
    store.upsert(table: :accounts, attributes: account.merge(name: Stweak::Domain::ValueMissing))
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)).not_to be_nil
  end

  it 'does not mint a key when every field is missing' do
    store.upsert(table: :accounts, attributes: account.merge(name: Stweak::Domain::ValueMissing,
                                                             email: Stweak::Domain::ValueMissing))
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: ACCOUNT_ID)).to be_nil
  end

  it 'reads an already-missing plaintext back as ValueMissing' do
    store.upsert(table: :accounts, attributes: account.merge(name: Stweak::Domain::ValueMissing,
                                                             email: Stweak::Domain::ValueMissing))
    expect(store.read_all(table: :accounts).first).to include(name: Stweak::Domain::ValueMissing,
                                                              email: Stweak::Domain::ValueMissing)
  end

  it 'passes through rows in tables with no PII columns' do
    passthrough = described_class.new(store: raw_store, cipher: cipher, key_store: key_store, pii: {})
    plain = { account_id: '1', name: 'kept' }
    passthrough.upsert(table: :accounts, attributes: plain)
    expect(passthrough.read_all(table: :accounts)).to eq([plain])
  end

  it 'passes row deletion through' do
    store.upsert(table: :accounts, attributes: account)
    store.delete_row(table: :accounts, id: ACCOUNT_ID.to_s)
    expect(store.read_all(table: :accounts)).to eq([])
  end

  it 'passes clearing a table through' do
    store.upsert(table: :accounts, attributes: account)
    store.clear(table: :accounts)
    expect(store.read_all(table: :accounts)).to eq([])
  end
end
