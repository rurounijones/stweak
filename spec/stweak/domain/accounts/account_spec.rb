# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/accounts/account_disabled'
require_relative '../../../../lib/stweak/domain/accounts/account_deleted'

# Concise builders for the account value objects, to keep examples short.
def make_username(value) = Stweak::Domain::Accounts::Username.new(value: value)
def make_display_name(value) = Stweak::Domain::Accounts::DisplayName.new(value: value)
def make_email(value) = Stweak::Domain::Accounts::Email.new(value: value)

# The time every example in this file creates accounts at.
CREATED_AT = Time.utc(2026, 1, 2, 3, 4, 5)

# Create an account with the given fields, defaulting to Alice's.
def create_account_on(target, username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com')
  target.create(username: make_username(username), password_hash: password_hash, name: make_display_name(name),
                email: make_email(email), occurred_at: CREATED_AT)
end

# Restore a checkpoint of Alice's account, overriding the shred-sensitive
# fields and the created flag as a test needs.
def restore_alice(target, name: 'Alice', email: 'alice@example.com', created: true)
  target.restore(
    'created' => created, 'username' => 'alice', 'password_hash' => 'hash', 'name' => name, 'email' => email
  )
end

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

# An AccountCreated event at the given position in a stream, with a username
# and name derived from its sequence.
def build_created_event(account_id, occurred_at, sequence)
  Stweak::Domain::Accounts::AccountCreated.new(
    stream_id: account_id, sequence: sequence, occurred_at: occurred_at, account_id: account_id,
    username: make_username("user-#{sequence}"), password_hash: 'hash',
    name: make_display_name("Name #{sequence}"), email: make_email("user#{sequence}@example.com")
  )
end

# A run of AccountCreated events at sequences 1..count on one stream.
def created_events(account_id, occurred_at, count)
  (1..count).map { |sequence| build_created_event(account_id, occurred_at, sequence) }
end

# An account rebuilt by replaying a run of created events.
def replayed_account(account_id, occurred_at, count)
  Stweak::Domain::Accounts::Account.replay(id: account_id, events: created_events(account_id, occurred_at, count))
end

# An account rebuilt from a checkpoint, replaying only the events after it.
def restored_from(checkpoint, account_id, occurred_at, count)
  Stweak::Domain::Accounts::Account.replay(
    id: account_id,
    events: created_events(account_id, occurred_at, count).drop(checkpoint.version),
    checkpoint: checkpoint
  )
end

# The state an account exposes, for comparing a restored account with a
# replayed one.
def state_fields(account)
  [account.created, account.disabled, account.deleted, account.username, account.name, account.email,
   account.password_hash]
end

RSpec.describe Stweak::Domain::Accounts::Account do
  subject(:account) { described_class.new(id: account_id) }

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:occurred_at) { Time.utc(2026, 1, 2, 3, 4, 5) }

  let(:created_event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id, sequence: 1, occurred_at: occurred_at, account_id: account_id,
      username: make_username('alice'), password_hash: 'hash',
      name: make_display_name('Alice'), email: make_email('alice@example.com')
    )
  end

  describe 'a fresh account' do
    it 'is not created' do
      expect(account.created).to be(false)
    end

    it 'has no username' do
      expect(account.username).to be(Stweak::Domain::ValueMissing)
    end

    it 'has an empty password hash' do
      expect(account.password_hash).to eq('')
    end

    it 'has no name' do
      expect(account.name).to be(Stweak::Domain::ValueMissing)
    end

    it 'has no email' do
      expect(account.email).to be(Stweak::Domain::ValueMissing)
    end
  end

  describe '#create' do
    before { create_account_on(account) }

    it 'numbers created events from the aggregate position' do
      fresh = described_class.new(id: account_id)
      fresh.advance_to(5)
      create_account_on(fresh)
      expect(fresh.uncommitted_events.first.sequence).to eq(6)
    end

    it 'emits an AccountCreated event' do
      expect(account.uncommitted_events).to eq([created_event])
    end

    it 'marks the account as created' do
      expect(account.created).to be(true)
    end

    it 'exposes the username' do
      expect(account.username).to eq(Stweak::Domain::Accounts::Username.new(value: 'alice'))
    end

    it 'exposes the password hash' do
      expect(account.password_hash).to eq('hash')
    end

    it 'exposes the name' do
      expect(account.name).to eq(Stweak::Domain::Accounts::DisplayName.new(value: 'Alice'))
    end

    it 'exposes the email' do
      expect(account.email).to eq(Stweak::Domain::Accounts::Email.new(value: 'alice@example.com'))
    end

    it 'refuses a second create, naming the account' do
      expect { create_account_on(account, username: 'bob', password_hash: 'hash2', name: 'Bob', email: 'b@x.com') }
        .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists, /#{account_id}.*already exists/)
    end
  end

  describe '#disable' do
    before { create_account_on(account) }

    it 'marks the account disabled' do
      account.disable(occurred_at: occurred_at)
      expect(account.disabled).to be(true)
    end

    it 'emits an AccountDisabled event' do
      account.disable(occurred_at: occurred_at)
      expect(account.uncommitted_events.last).to be_a(Stweak::Domain::Accounts::AccountDisabled)
    end

    it 'numbers the disabled event from the aggregate position' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      rebuilt.disable(occurred_at: occurred_at)
      expect(rebuilt.uncommitted_events.last.sequence).to eq(2)
    end

    it 'preserves the account data' do
      account.disable(occurred_at: occurred_at)
      expect([account.username.to_s, account.name.pii, account.email.pii]).to eq(%w[alice Alice alice@example.com])
    end

    it 'rejects disabling an already disabled account, naming the account' do
      account.disable(occurred_at: occurred_at)
      expect { account.disable(occurred_at: occurred_at) }
        .to raise_error(Stweak::Domain::Accounts::AccountAlreadyDisabled, /#{account_id} is already disabled/)
    end

    it 'rejects disabling a deleted account, naming the account' do
      account.delete(occurred_at: occurred_at)
      expect { account.disable(occurred_at: occurred_at) }
        .to raise_error(Stweak::Domain::Accounts::AccountAlreadyDeleted, /#{account_id} is already deleted/)
    end

    it 'rejects disabling an account that does not exist, naming the account' do
      fresh = described_class.new(id: account_id)
      expect { fresh.disable(occurred_at: occurred_at) }
        .to raise_error(Stweak::Domain::Accounts::AccountNotFound, /#{account_id} does not exist/)
    end
  end

  describe '#delete' do
    before { create_account_on(account) }

    it 'marks the account deleted' do
      account.delete(occurred_at: occurred_at)
      expect(account.deleted).to be(true)
    end

    it 'emits an AccountDeleted event' do
      account.delete(occurred_at: occurred_at)
      expect(account.uncommitted_events.last).to be_a(Stweak::Domain::Accounts::AccountDeleted)
    end

    it 'numbers the deleted event from the aggregate position' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      rebuilt.delete(occurred_at: occurred_at)
      expect(rebuilt.uncommitted_events.last.sequence).to eq(2)
    end

    it 'rejects deleting an already deleted account, naming the account' do
      account.delete(occurred_at: occurred_at)
      expect { account.delete(occurred_at: occurred_at) }
        .to raise_error(Stweak::Domain::Accounts::AccountAlreadyDeleted, /#{account_id} is already deleted/)
    end

    it 'rejects deleting an account that does not exist, naming the account' do
      fresh = described_class.new(id: account_id)
      expect { fresh.delete(occurred_at: occurred_at) }
        .to raise_error(Stweak::Domain::Accounts::AccountNotFound, /#{account_id} does not exist/)
    end
  end

  describe '.replay' do
    let(:lifecycle_events) do
      [created_event,
       Stweak::Domain::Accounts::AccountDisabled.new(stream_id: account_id, sequence: 2, occurred_at: occurred_at),
       Stweak::Domain::Accounts::AccountDeleted.new(stream_id: account_id, sequence: 3, occurred_at: occurred_at)]
    end

    it 'marks a replayed account as created' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.created).to be(true)
    end

    it 'replays the disabled state' do
      rebuilt = described_class.replay(id: account_id, events: lifecycle_events)
      expect(rebuilt.disabled).to be(true)
    end

    it 'replays the deleted state' do
      rebuilt = described_class.replay(id: account_id, events: lifecycle_events)
      expect(rebuilt.deleted).to be(true)
    end

    it 'restores the username' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.username).to eq(Stweak::Domain::Accounts::Username.new(value: 'alice'))
    end

    it 'restores the name' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.name).to eq(Stweak::Domain::Accounts::DisplayName.new(value: 'Alice'))
    end

    it 'restores the email' do
      rebuilt = described_class.replay(id: account_id, events: [created_event])
      expect(rebuilt.email).to eq(Stweak::Domain::Accounts::Email.new(value: 'alice@example.com'))
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

  describe 'checkpointing' do
    it 'restores its state from a checkpoint' do
      restore_alice(account)
      expect(state_fields(account)).to eq([true, false, false, make_username('alice'), make_display_name('Alice'),
                                           make_email('alice@example.com'), 'hash'])
    end

    it 'restores a shredded name and email as the marker, not a value object' do
      restore_alice(account, name: Stweak::Domain::ValueMissing, email: Stweak::Domain::ValueMissing)
      expect([account.name, account.email]).to eq([Stweak::Domain::ValueMissing, Stweak::Domain::ValueMissing])
    end

    it 'checkpoints a shredded name and email as the marker, not a string' do
      restore_alice(account, name: Stweak::Domain::ValueMissing, email: Stweak::Domain::ValueMissing)
      expect(account.checkpoint_state.values_at('name', 'email'))
        .to eq([Stweak::Domain::ValueMissing, Stweak::Domain::ValueMissing])
    end

    it 'restores the created flag from its value, not its presence' do
      restore_alice(account, created: false)
      expect(account.created).to be(false)
    end

    it 'restores the disabled and deleted flags from their stored values' do
      account.restore('created' => true, 'disabled' => true, 'deleted' => true, 'username' => 'alice',
                      'password_hash' => 'hash', 'name' => 'Alice', 'email' => 'alice@example.com')
      expect([account.disabled, account.deleted]).to eq([true, true])
    end

    it 'checkpoints the state at the hundredth event' do
      checkpoint = replayed_account(account_id, occurred_at, 100).checkpoint
      expect(checkpoint.state).to eq(
        'created' => true, 'disabled' => false, 'deleted' => false, 'username' => 'user-100',
        'password_hash' => 'hash', 'name' => 'Name 100', 'email' => 'user100@example.com'
      )
    end

    it 'produces no checkpoint before a hundred events' do
      rebuilt = replayed_account(account_id, occurred_at, 50)
      expect(rebuilt.checkpoint).to be_nil
    end

    it 'restoring from a checkpoint and replaying the tail equals a full replay' do
      full = replayed_account(account_id, occurred_at, 150)
      checkpoint = replayed_account(account_id, occurred_at, 100).checkpoint
      restored = restored_from(checkpoint, account_id, occurred_at, 150)
      expect(state_fields(restored)).to eq(state_fields(full))
    end

    it 'declares its display name and email as checkpoint PII' do
      expect(described_class.checkpoint_pii_fields).to eq(%i[name email])
    end
  end
end
