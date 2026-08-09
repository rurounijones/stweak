# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/checkpoint_store/in_memory'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/checkpoint'
require_relative '../../../support/checkpoint_store_examples'
require_relative '../../../support/property/generators'

# The aggregate class whose checkpoints the examples store, short so that
# example bodies fit on one line.
ACCOUNT_TYPE = Stweak::Domain::Accounts::Account

# A second aggregate type, so the checkpoint store can be shown to qualify
# checkpoints by the owner's class rather than trusting the owner's id to be
# unique on its own.
class OtherAggregate < Stweak::Domain::Aggregate
  def apply(_event)
    nil
  end
end

# A checkpoint carrying the given state at the given version.
def checkpoint(state, version)
  Stweak::Domain::Checkpoint.new(state: state, version: version)
end

# Stores a checkpoint for an Account with the given raw id, returning the
# [id, checkpoint] pair so the round-trip can be read back.
def store_checkpoint(store, raw_id, state, version)
  id = Stweak::Domain::Id.new(value: raw_id)
  snapshot = checkpoint(state, version)
  store.put(owner_type: ACCOUNT_TYPE, owner_id: id, checkpoint: snapshot)
  [id, snapshot]
end

RSpec.describe Stweak::Adapters::CheckpointStore::InMemoryCheckpointStore do
  include PropertyGenerators

  subject(:store) { described_class.new }

  let(:owner_id) { Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa') }

  it_behaves_like 'a checkpoint store'

  it 'keeps the same id apart across owner classes' do
    store.put(owner_type: ACCOUNT_TYPE, owner_id: owner_id, checkpoint: checkpoint({ 'username' => 'alice' }, 100))
    store.put(owner_type: OtherAggregate, owner_id: owner_id, checkpoint: checkpoint({ 'level' => 3 }, 50))

    expect(store.get(owner_type: ACCOUNT_TYPE, owner_id: owner_id).state).to eq('username' => 'alice')
  end

  it 'deleting one owner class leaves the other with the same id intact' do
    store.put(owner_type: ACCOUNT_TYPE, owner_id: owner_id, checkpoint: checkpoint({ 'username' => 'alice' }, 100))
    store.put(owner_type: OtherAggregate, owner_id: owner_id, checkpoint: checkpoint({ 'level' => 3 }, 50))
    store.delete(owner_type: ACCOUNT_TYPE, owner_id: owner_id)

    expect(store.get(owner_type: OtherAggregate, owner_id: owner_id).state).to eq('level' => 3)
  end

  it 'round-trips a checkpoint for any owner id, state and version', :property do
    PropCheck.forall(uuid, string, choose(0..1000)) do |owner_id, state_value, version|
      id, checkpoint = store_checkpoint(store, owner_id, { 'value' => state_value }, version)
      expect(store.get(owner_type: ACCOUNT_TYPE, owner_id: id)).to eq(checkpoint)
    end
  end
end
