# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/accounts/account'
require_relative '../../lib/stweak/domain/checkpoint'
require_relative '../../lib/stweak/domain/id'

# Owner ids the shared examples exercise the checkpoint store with.
CHECKPOINT_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa')
MISSING_CHECKPOINT_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000bb')

# Store `checkpoint` for the shared CHECKPOINT_ID in `store`. A top-level helper
# rather than a method in the shared block, which Sorbet forbids.
def store_shared_checkpoint(store, checkpoint)
  store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID, checkpoint: checkpoint)
end

# The checkpoint stored for the shared CHECKPOINT_ID in `store`, or nil.
def stored_shared_checkpoint(store)
  store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID)
end

# The contract every checkpoint store must honour. Any future durable
# implementation is held to this before it is trusted with real checkpoints.
RSpec.shared_examples 'a checkpoint store' do
  let(:stored_checkpoint) { Stweak::Domain::Checkpoint.new(state: { 'username' => 'alice' }, version: 100) }

  it 'returns a stored checkpoint' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID, checkpoint: stored_checkpoint)
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID))
      .to eq(stored_checkpoint)
  end

  it 'replaces an existing checkpoint' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID, checkpoint: stored_checkpoint)
    later = Stweak::Domain::Checkpoint.new(state: { 'username' => 'bob' }, version: 200)
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID, checkpoint: later)
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID)).to eq(later)
  end

  it 'returns nil for a missing checkpoint' do
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: MISSING_CHECKPOINT_ID)).to be_nil
  end

  it 'deletes a stored checkpoint' do
    subject.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID, checkpoint: stored_checkpoint)
    subject.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID)
    expect(subject.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: CHECKPOINT_ID)).to be_nil
  end

  it 'deleting a missing checkpoint does not raise' do
    expect { subject.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: MISSING_CHECKPOINT_ID) }
      .not_to raise_error
  end

  it 'returns a distinct object, not the stored checkpoint' do
    store_shared_checkpoint(subject, stored_checkpoint)
    expect(stored_shared_checkpoint(subject)).not_to be(stored_checkpoint)
  end

  it 'does not reflect mutation of the caller state after storing' do
    state = { 'username' => 'alice' }
    store_shared_checkpoint(subject, Stweak::Domain::Checkpoint.new(state: state, version: 100))
    state['username'] = 'mutated'
    expect(stored_shared_checkpoint(subject).state).to eq('username' => 'alice')
  end

  it 'is unaffected by mutation of a returned checkpoint state' do
    store_shared_checkpoint(subject, stored_checkpoint)
    stored_shared_checkpoint(subject).state['username'] = 'mutated'
    expect(stored_shared_checkpoint(subject).state).to eq('username' => 'alice')
  end
end
