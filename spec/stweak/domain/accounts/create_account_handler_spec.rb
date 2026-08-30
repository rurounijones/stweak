# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account_handler'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/checkpoint'
require_relative '../../../../lib/stweak/domain/security/password_hasher'
require_relative '../../../../lib/stweak/ports/event_store'
require_relative '../../../../lib/stweak/ports/checkpoint_store'
require_relative '../../../../lib/stweak/ports/usernames'
require_relative '../../../support/property/domain_generators'

# Concise builders for the account value objects, to keep examples short.
def a_username(value) = Stweak::Domain::Accounts::Username.new(value: value)
def a_display_name(value) = Stweak::Domain::Accounts::DisplayName.new(value: value)

ACCOUNT_OWNER_TYPE = Stweak::Domain::Accounts::Account
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OTHER_ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000002')

# A run of AccountCreated events at sequences 1..count on one stream, so an
# account can be replayed to any length — including a checkpoint boundary —
# without an event store behind it.
def account_created_events(account_id, count)
  (1..count).map do |sequence|
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id, sequence: sequence, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5), account_id: account_id,
      username: Stweak::Domain::Accounts::Username.new(value: "user-#{sequence}"), password_hash: 'hash',
      name: Stweak::Domain::Accounts::DisplayName.new(value: "Name #{sequence}"),
      email: Stweak::Domain::Accounts::Email.new(value: "user#{sequence}@example.com")
    )
  end
end

# An account replayed from count events, standing in for one loaded from a
# stream of that length.
def account_at(account_id, count)
  Stweak::Domain::Accounts::Account.replay(id: account_id, events: account_created_events(account_id, count))
end

# A checkpoint of a created account at version 100, for exercising the
# handler's load path against a stored checkpoint.
def created_account_checkpoint
  Stweak::Domain::Checkpoint.new(
    state: { 'created' => true, 'username' => 'alice', 'password_hash' => 'hash', 'name' => 'Alice',
             'email' => 'alice@example.com' },
    version: 100
  )
end

# Builds a CreateAccount command, defaulting every field except the id.
def build_create_account_command(account_id:, username: 'alice', password: 'hunter2', name: 'Alice',
                                 email: 'alice@example.com')
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: account_id,
    username: Stweak::Domain::Accounts::Username.new(value: username),
    password: password,
    name: Stweak::Domain::Accounts::DisplayName.new(value: name),
    email: Stweak::Domain::Accounts::Email.new(value: email)
  )
end

# The username is derived from the account id, so commands generated for the
# property can never collide on the username across iterations.
def command_with_unique_username(command)
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: command.account_id,
    username: Stweak::Domain::Accounts::Username.new(value: "user-#{command.account_id}"),
    password: command.password,
    name: command.name,
    email: command.email
  )
end

# The state an account exposes, for comparing a handled account with one
# replayed from the events the handler appended.
def account_state(account)
  [account.created, account.disabled, account.deleted, account.username, account.name,
   account.password_hash]
end

# The events the handler appended for one stream, in append order, drawn from
# the recorded append calls.
def appended_events(appends, stream_id)
  appends.select { |call| call.fetch(:stream_id) == stream_id }.flat_map { |call| call.fetch(:events) }
end

RSpec.describe Stweak::Domain::Accounts::CreateAccountHandler do
  include DomainPropertyGenerators

  subject(:handler) do
    described_class.new(
      event_store: event_store,
      password_hasher: password_hasher,
      checkpoint_store: checkpoint_store,
      usernames: usernames
    )
  end

  let(:event_store) { instance_double(Stweak::Ports::EventStore) }
  let(:password_hasher) { instance_double(Stweak::Domain::Security::PasswordHasher) }
  let(:checkpoint_store) { instance_double(Stweak::Ports::CheckpointStore) }
  let(:usernames) { instance_double(Stweak::Ports::Usernames) }

  # Every append the handler makes, in order, so its writes can be inspected
  # and — for the property — replayed back into an account.
  let(:appends) { [] }

  before do
    # A fresh account by default: no checkpoint, an empty stream, and a free
    # username. Each example that needs an existing account overrides these.
    allow(checkpoint_store).to receive(:get).and_return(nil)
    allow(checkpoint_store).to receive(:put)
    allow(event_store).to receive(:read_stream).and_return([])
    allow(usernames).to receive(:include?).and_return(false)
    allow(password_hasher).to receive(:digest) { |password:| "digest-of-#{password}" }
    allow(event_store).to receive(:append) { |**call| appends << call }
  end

  it 'creates the account' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.created).to be(true)
  end

  it 'appends one AccountCreated event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).map(&:class)).to eq([Stweak::Domain::Accounts::AccountCreated])
  end

  it 'appends on the account stream at the expected version' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appends.last).to include(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID, expected_version: 0)
  end

  it 'stamps created_at on the appended event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.created_at).to be_within(2).of(Time.now)
  end

  it 'stores the username in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.username)
      .to eq(Stweak::Domain::Accounts::Username.new(value: 'alice'))
  end

  it 'stores the plaintext name in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.name)
      .to eq(Stweak::Domain::Accounts::DisplayName.new(value: 'Alice'))
  end

  it 'hashes the command password through the hasher' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(password_hasher).to have_received(:digest).with(password: 'hunter2')
  end

  it 'stores the digest the hasher produced, never the raw password' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.password_hash).to eq('digest-of-hunter2')
  end

  it 'stores the same digest in the event' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(appended_events(appends, ACCOUNT_ID).first.password_hash).to eq(account.password_hash)
  end

  it 'rejects creating the same account twice' do
    allow(event_store).to receive(:read_stream).and_return(account_created_events(ACCOUNT_ID, 1))
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'rejects a username another account already uses' do
    allow(usernames).to receive(:include?)
      .with(Stweak::Domain::Accounts::Username.new(value: 'alice')).and_return(true)
    expect { handler.handle(build_create_account_command(account_id: OTHER_ACCOUNT_ID)) }
      .to raise_error(Stweak::Domain::Accounts::UsernameTaken, /username alice is already in use/)
  end

  it 'allows a free username' do
    account = handler.handle(build_create_account_command(account_id: OTHER_ACCOUNT_ID, username: 'bob'))
    expect(account.created).to be(true)
  end

  it 'reports the account conflict, not a username collision, for a recreated account' do
    allow(event_store).to receive(:read_stream).and_return(account_created_events(ACCOUNT_ID, 1))
    allow(usernames).to receive(:include?)
      .with(Stweak::Domain::Accounts::Username.new(value: 'bob')).and_return(true)
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'returns the account for a retried create' do
    allow(event_store).to receive(:read_stream).and_return([account_created_events(ACCOUNT_ID, 1).first])
    retried = handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'user-1'))
    expect(account_state(retried)).to eq([true, false, false, a_username('user-1'), a_display_name('Name 1'), 'hash'])
  end

  it 'does not append a second event for a retried create' do
    allow(event_store).to receive(:read_stream).and_return([account_created_events(ACCOUNT_ID, 1).first])
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'user-1'))
    expect(event_store).not_to have_received(:append)
  end

  it 'surfaces a concurrent append as AccountAlreadyExists' do
    allow(event_store).to receive(:append).and_raise(Stweak::Ports::ConcurrencyError)
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID)) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'writes no checkpoint before a hundred events' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(checkpoint_store).not_to have_received(:put)
  end

  it 'persists the account checkpoint on its own stream at a boundary' do
    handler.send(:append, account_at(ACCOUNT_ID, 100))
    expect(checkpoint_store).to have_received(:put)
      .with(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID, checkpoint: have_attributes(version: 100))
  end

  it 'restores a stored checkpoint when loading an account' do
    allow(checkpoint_store).to receive(:get).and_return(created_account_checkpoint)
    expect(handler.send(:load_account, ACCOUNT_ID).username)
      .to eq(Stweak::Domain::Accounts::Username.new(value: 'alice'))
  end

  it 'loads the checkpoint for the account being loaded' do
    handler.send(:load_account, ACCOUNT_ID)
    expect(checkpoint_store).to have_received(:get).with(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID)
  end

  it 'reads only the tail after the checkpoint version when loading an account' do
    allow(checkpoint_store).to receive(:get).and_return(created_account_checkpoint)
    handler.send(:load_account, ACCOUNT_ID)
    expect(event_store).to have_received(:read_stream)
      .with(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID, after: 100)
  end

  it 'reads the whole stream when no checkpoint is stored' do
    handler.send(:load_account, ACCOUNT_ID)
    expect(event_store).to have_received(:read_stream)
      .with(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID, after: 0)
  end

  it 'writes events that replay to the account it returned', :property do
    PropCheck.forall(create_account_command) do |command|
      handled = handler.handle(command_with_unique_username(command))
      replayed = Stweak::Domain::Accounts::Account.replay(id: handled.id, events: appended_events(appends, handled.id))
      expect(account_state(replayed)).to eq(account_state(handled))
    end
  end
end
