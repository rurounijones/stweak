# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
# A non-AccountCreated event, to exercise the unknown-event branch of apply.
class OtherAccountEvent < Stweak::Domain::Event
  VERSION = 1
  TYPE = 'OtherAccountEvent'

  def type
    TYPE
  end

  def version
    VERSION
  end
end

RSpec.describe Stweak::Domain::Accounts::Account do
  subject(:account) { described_class.new(id: account_id) }

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:occurred_at) { Time.utc(2026, 1, 2, 3, 4, 5) }

  let(:created_event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id,
      sequence: 1,
      occurred_at: occurred_at,
      account_id: account_id,
      username: 'alice',
      password_hash: 'hash',
      name: 'Alice',
      email: 'alice@example.com'
    )
  end

  describe 'a fresh account' do
    it 'is not created' do
      expect(account.created).to be(false)
    end

    it 'has an empty username' do
      expect(account.username).to eq('')
    end

    it 'has an empty password hash' do
      expect(account.password_hash).to eq('')
    end

    it 'has an empty name' do
      expect(account.name).to eq('')
    end

    it 'has an empty email' do
      expect(account.email).to eq('')
    end
  end

  describe '#create' do
    before do
      account.create(username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com',
                     occurred_at: occurred_at)
    end

    it 'numbers created events from the aggregate position' do
      fresh = described_class.new(id: account_id)
      fresh.advance_to(5)
      fresh.create(username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com',
                   occurred_at: occurred_at)
      expect(fresh.uncommitted_events.first.sequence).to eq(6)
    end

    it 'emits an AccountCreated event' do
      expect(account.uncommitted_events).to eq([created_event])
    end

    it 'marks the account as created' do
      expect(account.created).to be(true)
    end

    it 'exposes the username' do
      expect(account.username).to eq('alice')
    end

    it 'exposes the password hash' do
      expect(account.password_hash).to eq('hash')
    end

    it 'exposes the name' do
      expect(account.name).to eq('Alice')
    end

    it 'exposes the email' do
      expect(account.email).to eq('alice@example.com')
    end

    it 'refuses a second create, naming the account' do
      expect do
        account.create(username: 'bob', password_hash: 'hash2', name: 'Bob', email: 'bob@example.com',
                       occurred_at: occurred_at)
      end.to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists, /#{account_id}.*already exists/)
    end
  end

  describe '.replay' do
    it 'marks a replayed account as created' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.created).to be(true)
    end

    it 'restores the username' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.username).to eq('alice')
    end

    it 'restores the name' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.name).to eq('Alice')
    end

    it 'restores the email' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.email).to eq('alice@example.com')
    end

    it 'tracks the expected version' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.expected_version).to eq(1)
    end

    it 'replays an empty stream to a fresh account' do
      rebuilt = described_class.replay(id: account_id, events: [])
      expect(rebuilt.created).to be(false)
    end

    it 'replays an empty stream at version zero' do
      rebuilt = described_class.replay(id: account_id, events: [])
      expect(rebuilt.expected_version).to eq(0)
    end

    it 'rejects an event it does not know, naming the account and event' do
      other = OtherAccountEvent.new(stream_id: account_id, sequence: 1, occurred_at: occurred_at)
      expect { described_class.replay(id: account_id, events: [other]) }
        .to raise_error(ArgumentError, /#{account_id}.*does not know event OtherAccountEvent/)
    end
  end
end
