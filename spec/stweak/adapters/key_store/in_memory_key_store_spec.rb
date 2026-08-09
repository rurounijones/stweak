# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../support/key_store_examples'
require_relative '../../../support/property/generators'
# A second aggregate type, so the key store can be shown to qualify keys by the
# owner's class rather than trusting the owner's id to be unique on its own.
class OtherAggregate < Stweak::Domain::Aggregate
  def apply(_event)
    nil
  end
end

RSpec.describe Stweak::Adapters::KeyStore::InMemoryKeyStore do
  include PropertyGenerators

  subject(:key_store) { described_class.new }

  let(:owner_id) { Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa') }

  it_behaves_like 'a key store'

  it 'keeps the same id apart across owner classes' do
    key_store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: owner_id, key: 'account-key')
    key_store.put(owner_type: OtherAggregate, owner_id: owner_id, key: 'player-key')

    expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: owner_id)).to eq('account-key')
  end

  it 'deleting one owner class leaves the other with the same id intact' do
    key_store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: owner_id, key: 'account-key')
    key_store.put(owner_type: OtherAggregate, owner_id: owner_id, key: 'player-key')
    key_store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: owner_id)

    expect(key_store.get(owner_type: OtherAggregate, owner_id: owner_id)).to eq('player-key')
  end

  it 'round-trips a key for any owner id and key', :property do
    PropCheck.forall(uuid, string) do |owner_id, key|
      id = Stweak::Domain::Id.new(value: owner_id)
      key_store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: id, key: key)
      expect(key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: id)).to eq(key)
    end
  end
end
