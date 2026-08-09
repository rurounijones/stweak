# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require 'sqlite3'
require 'tmpdir'
require_relative '../spec_helper'
require_relative '../../projection_store/sqlite'
require_relative '../../../../spec/support/projection_store_examples'

RSpec.describe App::Adapters::SqliteProjectionStore do
  subject(:store) { described_class.new(db: db) }

  let(:db) { SQLite3::Database.new(':memory:') }

  # A store on a file, so its writes can be read back by a second connection,
  # as a restarted process would.
  let(:path) { File.join(Dir.tmpdir, "stweak_projection_#{object_id}.db") }
  let(:first_store) { described_class.new(db: SQLite3::Database.new(path)) }
  let(:row) do
    { account_id: '1', username: 'alice', password_hash: 'h', name_cipher: 'n', email_cipher: 'e', created_at: 't' }
  end

  it_behaves_like 'a projection store'

  it 'rejects a table it does not host' do
    expect { store.upsert(table: :unknown, attributes: {}) }.to raise_error(ArgumentError, /unknown/)
  end

  it 'survives a reconnect, so a restarted projector resumes its cursors' do
    first_store.write(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
    reopened = described_class.new(db: SQLite3::Database.new(path))
    expect(reopened.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 1)
  end

  it 'runs projection changes in one transaction' do
    store.transaction do
      store.upsert(table: :accounts, attributes: row)
      store.advance(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
    end

    expect(store.read_all(table: :accounts)).to eq([row])
    expect(store.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 1)
  end

  it 'rolls back rows and cursors together when a transaction fails' do
    expect do
      store.transaction do
        store.upsert(table: :accounts, attributes: row)
        store.advance(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
        raise 'failed projection'
      end
    end.to raise_error('failed projection')

    expect(store.read_all(table: :accounts)).to eq([])
    expect(store.read(projection_name: 'AccountsProjector')).to be_nil
  end

  it 'advances one cursor while retaining other cursors' do
    first_store.write(
      projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1, 'Account#2' => 1 }
    )
    first_store.advance(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 2 })

    expect(first_store.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 2, 'Account#2' => 1)
  end

  it 'does not move a cursor backwards' do
    store.write(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 2 })
    store.advance(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })

    expect(store.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 2)
  end

  it 'survives a reconnect, so a restarted projector keeps its rows' do
    first_store.upsert(table: :accounts, attributes: row)
    reopened = described_class.new(db: SQLite3::Database.new(path))
    expect(reopened.read_all(table: :accounts)).to eq([row])
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
