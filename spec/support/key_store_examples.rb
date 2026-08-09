# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/accounts/account'
require_relative '../../lib/stweak/domain/id'

# Owner ids the shared examples exercise the key store with.
KEY_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa')
MISSING_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000bb')

# Store `key` for the shared KEY_ID in `store`. A top-level helper rather than a
# method in the shared block, which Sorbet forbids.
def store_shared_key(store, key)
  store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID, key: key)
end

# The key stored for the shared KEY_ID in `store`, or nil.
def stored_shared_key(store)
  store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID)
end

# The contract every key store must honour. Any future durable implementation
# is held to this before it is trusted with real keys.
RSpec.shared_examples 'a key store' do
  it 'returns a stored key' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID, key: 'key-data')
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID)).to eq('key-data')
  end

  it 'replaces an existing key' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID, key: 'first')
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID, key: 'second')
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID)).to eq('second')
  end

  it 'returns nil for a missing key' do
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: MISSING_ID)).to be_nil
  end

  it 'deletes a stored key' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID, key: 'key-data')
    subject.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID)
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: KEY_ID)).to be_nil
  end

  it 'deleting a missing key does not raise' do
    expect { subject.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: MISSING_ID) }.not_to raise_error
  end

  it 'returns a distinct string, not the stored key' do
    key = +'key-data'
    store_shared_key(subject, key)
    expect(stored_shared_key(subject)).not_to be(key)
  end

  it 'is unaffected by mutation of a returned key' do
    store_shared_key(subject, 'key-data')
    stored_shared_key(subject) << 'tampered'
    expect(stored_shared_key(subject)).to eq('key-data')
  end

  it 'does not reflect mutation of the caller key after storing' do
    key = +'key-data'
    store_shared_key(subject, key)
    key << 'tampered'
    expect(stored_shared_key(subject)).to eq('key-data')
  end
end
