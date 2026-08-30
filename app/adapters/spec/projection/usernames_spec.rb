# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../projection/usernames'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'

# An account row with the given username, as the projector would write it.
def account(username)
  {
    account_id: '00000000-0000-4000-8000-000000000001',
    username: username,
    password_hash: 'hash',
    name_cipher: 'n',
    email_cipher: 'e',
    created_at: '2026-01-02T03:04:05Z'
  }
end

RSpec.describe App::Adapters::Projection::Usernames do
  subject(:usernames) { described_class.new(store: store) }

  let(:store) { Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new }

  it 'sees a username once an account row carries it' do
    store.upsert(table: :accounts, attributes: account('alice'))
    expect(usernames.include?(Stweak::Domain::Accounts::Username.new(value: 'alice'))).to be(true)
  end

  it 'does not see an unused username' do
    store.upsert(table: :accounts, attributes: account('alice'))
    expect(usernames.include?(Stweak::Domain::Accounts::Username.new(value: 'bob'))).to be(false)
  end

  it 'sees no usernames when the table is empty' do
    expect(usernames.include?(Stweak::Domain::Accounts::Username.new(value: 'alice'))).to be(false)
  end
end
