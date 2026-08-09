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

  it 'reads one row by its primary key' do
    subject.upsert(table: :accounts, attributes: account)
    expect(subject.read_row(table: :accounts, id: account_id)).to eq(account)
  end

  it 'returns nil reading a row that is not present' do
    subject.upsert(table: :accounts, attributes: account)
    expect(subject.read_row(table: :accounts, id: 'no-such-id')).to be_nil
  end

  it 'returns nil reading a row from an empty table' do
    expect(subject.read_row(table: :accounts, id: account_id)).to be_nil
  end

  it 'returns a keyed row distinct from the upserted attributes' do
    subject.upsert(table: :accounts, attributes: account)
    expect(subject.read_row(table: :accounts, id: account_id)).not_to be(account)
  end

  it 'is unaffected by mutation of a keyed row' do
    subject.upsert(table: :accounts, attributes: account)
    subject.read_row(table: :accounts, id: account_id)[:username] = 'mutated'
    expect(subject.read_row(table: :accounts, id: account_id)).to eq(account)
  end

  it 'returns a row distinct from the upserted attributes' do
    subject.upsert(table: :accounts, attributes: account)
    expect(subject.read_all(table: :accounts).first).not_to be(account)
  end

  it 'does not reflect mutation of the attributes after upsert' do
    attributes = account.dup
    subject.upsert(table: :accounts, attributes: attributes)
    attributes[:username] = 'mutated'
    expect(subject.read_all(table: :accounts)).to eq([account])
  end

  it 'is unaffected by mutation of a returned row' do
    subject.upsert(table: :accounts, attributes: account)
    subject.read_all(table: :accounts).first[:username] = 'mutated'
    expect(subject.read_all(table: :accounts)).to eq([account])
  end

  it 'returns cursors distinct from the written hash' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    expect(subject.read(projection_name: 'AccountsProjector')).not_to be(cursors)
  end

  it 'does not reflect mutation of the cursors after writing' do
    writable = cursors.dup
    subject.write(projection_name: 'AccountsProjector', cursors: writable)
    writable[stream_key] = 99
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(cursors)
  end

  it 'is unaffected by mutation of a returned cursors hash' do
    subject.write(projection_name: 'AccountsProjector', cursors: cursors)
    subject.read(projection_name: 'AccountsProjector')[stream_key] = 99
    expect(subject.read(projection_name: 'AccountsProjector')).to eq(cursors)
  end
end
