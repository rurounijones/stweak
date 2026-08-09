# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../checkpoint_store/encrypting'
require_relative '../../../../lib/stweak/adapters/checkpoint_store/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'

CHECKPOINT_OWNER_TYPE = Stweak::Domain::Accounts::Account
CHECKPOINT_ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
CHECKPOINT_STATE = {
  'created' => true, 'username' => 'alice', 'password_hash' => 'hash', 'name' => 'Alice',
  'email' => 'alice@example.com'
}.freeze

# Puts a checkpoint carrying the given state through the store under test.
def put_checkpoint(store, state = CHECKPOINT_STATE, version: 100)
  store.put(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID,
            checkpoint: Stweak::Domain::Checkpoint.new(state: state, version: version))
end

# Gets the account's checkpoint back through the store under test.
def get_checkpoint(store)
  store.get(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID)
end

# The state as it sits at rest in the decorated store, before decryption.
def stored_state(raw_store)
  raw_store.get(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID).state
end

# The account's key as held in the key store, or nil if none was minted.
def stored_key(key_store)
  key_store.get(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID)
end

# Shreds the account's key, the GDPR erasure the decorator must tolerate.
def shred(key_store)
  key_store.delete(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID)
end

RSpec.describe App::Adapters::CheckpointStore::EncryptingCheckpointStore do
  subject(:store) do
    described_class.new(store: raw_store, cipher: cipher, key_store: key_store)
  end

  let(:raw_store) { Stweak::Adapters::CheckpointStore::InMemoryCheckpointStore.new }
  let(:cipher) { Stweak::Adapters::Encryption::AesGcm.new }
  let(:key_store) { Stweak::Adapters::KeyStore::InMemoryKeyStore.new }

  it 'stores the name as ciphertext' do
    put_checkpoint(store)
    expect(stored_state(raw_store)['name']).not_to eq('Alice')
  end

  it 'stores the email as ciphertext' do
    put_checkpoint(store)
    expect(stored_state(raw_store)['email']).not_to eq('alice@example.com')
  end

  it 'leaves the non-PII state untouched at rest' do
    put_checkpoint(store)
    expect(stored_state(raw_store)).to include('created' => true, 'username' => 'alice', 'password_hash' => 'hash')
  end

  it 'keeps the checkpoint version' do
    put_checkpoint(store)
    expect(raw_store.get(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID).version).to eq(100)
  end

  it 'round-trips the plaintext state on read' do
    put_checkpoint(store)
    expect(get_checkpoint(store).state).to eq(CHECKPOINT_STATE)
  end

  it 'creates a key for the account on first put' do
    put_checkpoint(store)
    expect(stored_key(key_store).bytesize).to eq(32)
  end

  it 'reuses the account key on a later put' do
    put_checkpoint(store)
    first = stored_key(key_store)
    put_checkpoint(store, CHECKPOINT_STATE.merge('name' => 'Alice Smith'), version: 200)
    expect(stored_key(key_store)).to eq(first)
  end

  it 'returns nil when the owner has no checkpoint' do
    expect(get_checkpoint(store)).to be_nil
  end

  it 'reads ValueMissing for the PII fields after the key is shredded' do
    put_checkpoint(store)
    shred(key_store)
    expect(get_checkpoint(store).state).to include('name' => Stweak::Domain::ValueMissing,
                                                   'email' => Stweak::Domain::ValueMissing)
  end

  it 'still reads non-PII state after the key is shredded' do
    put_checkpoint(store)
    shred(key_store)
    expect(get_checkpoint(store).state).to include('created' => true, 'username' => 'alice', 'password_hash' => 'hash')
  end

  it 'mints a key when some fields are still present' do
    put_checkpoint(store, CHECKPOINT_STATE.merge('name' => Stweak::Domain::ValueMissing))
    expect(stored_key(key_store)).not_to be_nil
  end

  it 'does not mint a key when every PII field is missing' do
    put_checkpoint(store, CHECKPOINT_STATE.merge('name' => Stweak::Domain::ValueMissing,
                                                 'email' => Stweak::Domain::ValueMissing))
    expect(stored_key(key_store)).to be_nil
  end

  it 'reads an already-missing plaintext back as ValueMissing' do
    put_checkpoint(store, CHECKPOINT_STATE.merge('name' => Stweak::Domain::ValueMissing,
                                                 'email' => Stweak::Domain::ValueMissing))
    expect(get_checkpoint(store).state).to include('name' => Stweak::Domain::ValueMissing,
                                                   'email' => Stweak::Domain::ValueMissing)
  end

  it 'passes through an owner that declares no PII fields' do
    plain = Class.new(Stweak::Domain::Aggregate)
    checkpoint = Stweak::Domain::Checkpoint.new(state: { 'name' => 'kept' }, version: 100)
    store.put(owner_type: plain, owner_id: CHECKPOINT_ACCOUNT_ID, checkpoint: checkpoint)
    expect(store.get(owner_type: plain, owner_id: CHECKPOINT_ACCOUNT_ID).state).to eq('name' => 'kept')
  end

  it 'passes checkpoint deletion through' do
    put_checkpoint(store)
    store.delete(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID)
    expect(raw_store.get(owner_type: CHECKPOINT_OWNER_TYPE, owner_id: CHECKPOINT_ACCOUNT_ID)).to be_nil
  end
end
