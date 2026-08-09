# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../projection/accounts_projector'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'

# The stream and owner the examples project from.
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OCCURRED_AT = Time.utc(2026, 1, 2, 3, 4, 5)

# An AccountCreated event, every field defaulted.
def created_event(username: 'alice', name: 'Alice', email: 'alice@example.com')
  Stweak::Domain::Accounts::AccountCreated.new(
    stream_id: ACCOUNT_ID, sequence: 1, occurred_at: OCCURRED_AT,
    account_id: ACCOUNT_ID, username: username, password_hash: 'hash', name: name, email: email
  )
end

# An event the accounts projector does not care about, so the ignore path can
# be exercised.
class SomeOtherEvent < Stweak::Domain::Event
  VERSION = 1

  def version
    VERSION
  end
end

RSpec.describe App::Adapters::Projection::AccountsProjector do
  subject(:projector) { described_class.new(store: store) }

  let(:store) { Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new }

  let(:expected_row) do
    {
      account_id: ACCOUNT_ID.to_s,
      username: 'alice',
      password_hash: 'hash',
      name: 'Alice',
      email: 'alice@example.com',
      created_at: OCCURRED_AT.iso8601
    }
  end

  it 'upserts the account row from an AccountCreated event' do
    projector.apply(created_event)
    expect(store.read_all(table: :accounts)).to eq([expected_row])
  end

  it 'replaces the row when the same account is created again' do
    projector.apply(created_event)
    projector.apply(created_event(name: 'Alice Smith'))
    expect(store.read_all(table: :accounts)).to eq([expected_row.merge(name: 'Alice Smith')])
  end

  it 'ignores events that are not AccountCreated' do
    projector.apply(SomeOtherEvent.new(stream_id: ACCOUNT_ID, sequence: 1, occurred_at: OCCURRED_AT))
    expect(store.read_all(table: :accounts)).to eq([])
  end

  it 'clears the accounts table when reset' do
    projector.apply(created_event)
    projector.reset
    expect(store.read_all(table: :accounts)).to eq([])
  end

  it 'derives its stable name from the class' do
    expect(projector.name).to eq('AccountsProjector')
  end
end
