# typed: false
# frozen_string_literal: true

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
    { account_id: '1', username: 'alice', disabled: 0, password_hash: 'h', name_cipher: 'n',
      email_cipher: 'e', created_at: 't' }
  end

  it_behaves_like 'a projection store'

  it 'rejects a table it does not host' do
    expect { store.upsert(table: :unknown, attributes: {}) }.to raise_error(ArgumentError, /unknown/)
  end

  it 'binds a true lifecycle flag as its integer form' do
    store.upsert(table: :accounts, attributes: row.merge(disabled: true))
    expect(store.read_all(table: :accounts).first[:disabled]).to eq(1)
  end

  it 'binds a false lifecycle flag as its integer form' do
    store.upsert(table: :accounts, attributes: row.merge(disabled: false))
    expect(store.read_all(table: :accounts).first[:disabled]).to eq(0)
  end

  it 'survives a reconnect, so a restarted projector resumes its cursors' do
    first_store.write(projection_name: 'AccountsProjector', cursors: { 'Account#1' => 1 })
    reopened = described_class.new(db: SQLite3::Database.new(path))
    expect(reopened.read(projection_name: 'AccountsProjector')).to eq('Account#1' => 1)
  end

  it 'survives a reconnect, so a restarted projector keeps its rows' do
    first_store.upsert(table: :accounts, attributes: row)
    reopened = described_class.new(db: SQLite3::Database.new(path))
    expect(reopened.read_all(table: :accounts)).to eq([row])
  end
end
