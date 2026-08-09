# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../support/property/domain_generators'
# An event with no PII fields, to exercise the pass-through path of the
# encrypting store.
class PlainEvent < Stweak::Domain::Event
  VERSION = 1
  TYPE = 'PlainEvent'

  def type
    TYPE
  end

  def version
    VERSION
  end
end

RSpec.describe Stweak::Adapters::EventStore::EncryptingEventStore do
  include DomainPropertyGenerators

  subject(:store) do
    described_class.new(
      store: raw_store,
      cipher: Stweak::Adapters::Encryption::AesGcm.new,
      key_store: key_store
    )
  end

  let(:raw_store) { Stweak::Adapters::EventStore::InMemoryEventStore.new }
  let(:key_store) { Stweak::Adapters::KeyStore::InMemoryKeyStore.new }
  let(:owner_type) { Stweak::Domain::Accounts::Account }
  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }

  let(:created_event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id,
      sequence: 1,
      occurred_at: Time.utc(2026, 1, 2, 3, 4, 5),
      account_id: account_id,
      username: 'alice',
      password_hash: 'hash',
      name: 'Alice',
      email: 'alice@example.com'
    )
  end

  it 'persists the name as ciphertext' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    stored = raw_store.read_stream(owner_type: owner_type, stream_id: account_id).first
    expect(stored.name).not_to eq('Alice')
  end

  it 'persists non-PII fields in plaintext' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    stored = raw_store.read_stream(owner_type: owner_type, stream_id: account_id).first
    expect(stored.username).to eq('alice')
  end

  it 'round-trips the plaintext on read' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id)).to eq([created_event])
  end

  it 'reads only the decrypted tail after a given sequence' do
    second_event = created_event.with('sequence' => 2, 'username' => 'bob', 'name' => 'Bob')
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0,
                 events: [created_event, second_event])
    tail = store.read_stream(owner_type: owner_type, stream_id: account_id, after: 1)
    expect(tail.map(&:name)).to eq(['Bob'])
  end

  it 'creates a key for the owner on first append' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id).bytesize).to eq(32)
  end

  it 'reuses the existing key on later appends' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    first = key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
    next_event = created_event.with('sequence' => 2)
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 1, events: [next_event])
    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)).to eq(first)
  end

  it 'reads ValueMissing for personal data after the key is shredded' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    key_store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
    event = store.read_stream(owner_type: owner_type, stream_id: account_id).first
    expect(event.name).to eq(Stweak::Domain::ValueMissing)
  end

  it 'still reads non-PII fields after the key is shredded' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    key_store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
    event = store.read_stream(owner_type: owner_type, stream_id: account_id).first
    expect(event.username).to eq('alice')
  end

  it 'passes events without PII through unchanged on append' do
    plain = PlainEvent.new(stream_id: account_id, sequence: 1, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5))
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [plain])
    expect(raw_store.read_stream(owner_type: owner_type, stream_id: account_id)).to eq([plain])
  end

  it 'passes events without PII through unchanged on read' do
    plain = PlainEvent.new(stream_id: account_id, sequence: 1, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5))
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [plain])
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id)).to eq([plain])
  end

  it 'yields each stream decrypted' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [created_event])
    yielded = []
    store.each_stream { |_owner, _id, events| yielded << events }
    expect(yielded).to eq([[created_event]])
  end

  it 'round-trips any event through encryption', :property do
    PropCheck.forall(account_created_event) do |event|
      event = event.with('sequence' => 1)
      store.append(owner_type: owner_type, stream_id: event.stream_id, expected_version: 0, events: [event])
      expect(store.read_stream(owner_type: owner_type, stream_id: event.stream_id)).to eq([event])
    end
  end
end
