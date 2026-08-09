# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/accounts/account'
require_relative '../../lib/stweak/domain/id'

# Owner ids the shared examples exercise the key store with.
KEY_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa')
MISSING_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000bb')

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
end
