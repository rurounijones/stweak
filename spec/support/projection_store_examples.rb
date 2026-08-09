# typed: false
# frozen_string_literal: true

# The contract every projection store must honour: cursor persistence and the
# row operations a projector writes its read model with. Any future durable
# implementation is held to this before it is trusted with real read models.
RSpec.shared_examples 'a projection store' do
  let(:stream_key) { "Stweak::Domain::Accounts::Account##{account_id}" }
  let(:account_id) { '00000000-0000-4000-8000-000000000001' }
  let(:cursors) { { stream_key => 1 } }

  let(:account) do
    {
      account_id: account_id,
      username: 'alice',
      password_hash: 'hash',
      name_cipher: 'Alice',
      email_cipher: 'alice@example.com',
      created_at: '2026-01-02T03:04:05Z'
    }
  end

  it 'returns stored cursors' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(cursors)
  end

  it 'replaces stored cursors' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    later = { 'Stweak::Domain::Accounts::Account#00000000-0000-4000-8000-000000000002' => 2 }
    subject.write(projection_name: 'AccountsProjector', cursors: later)
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(later)
  end

  it 'advances only the supplied cursors' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    later = { stream_key => 2, 'other-stream' => 1 }
    subject.advance(projection_name: 'AccountsProjector', cursors: later)
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(stream_key => 2, 'other-stream' => 1)
  end

  it 'does not move a cursor backwards' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    subject.advance(projection_name: 'AccountsProjector', cursors: { stream_key => 0 })
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(cursors)
  end

  it 'does not create a projection for an empty advance' do
    subject.advance(projection_name: 'AccountsProjector', cursors: {})
    expect(subject.read(projection_name: 'AccountsProjector')).to be_nil
  end

  it 'returns nil for a missing projection' do
    expect(subject.read(projection_name: 'Missing')).to be_nil
  end

  it 'deletes stored cursors' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    subject.delete(projection_name: 'AccountsProjector')
    expect(subject.read(projection_name: 'AccountsProjector')).to be_nil
  end

  it 'deleting a missing projection does not raise' do
    expect { subject.delete(projection_name: 'Missing') }.not_to raise_error
  end

  it 'upserts a row into a read-model table' do
    subject.upsert(table: :accounts, attributes: account)
    expect(subject.read_all(table: :accounts)).to eq([account])
  end

  it 'replaces a row upserted under the same key' do
    subject.upsert(table: :accounts, attributes: account)
    updated = account.merge(username: 'alice2')
    subject.upsert(table: :accounts, attributes: updated)
    expect(subject.read_all(table: :accounts)).to eq([updated])
  end

  it 'deletes a row' do
    subject.upsert(table: :accounts, attributes: account)
    subject.delete_row(table: :accounts, id: account_id)
    expect(subject.read_all(table: :accounts)).to eq([])
  end

  it 'clears a read-model table' do
    subject.upsert(table: :accounts, attributes: account)
    subject.clear(table: :accounts)
    expect(subject.read_all(table: :accounts)).to eq([])
  end

  it 'returns no rows for an empty table' do
    expect(subject.read_all(table: :accounts)).to eq([])
  end
end
