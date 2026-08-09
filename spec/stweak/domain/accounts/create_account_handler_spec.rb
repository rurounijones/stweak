# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/domain/accounts/create_account_handler'
require_relative '../../../../lib/stweak/domain/accounts/create_account'
require_relative '../../../../lib/stweak/domain/projection_system'
require_relative '../../../support/property/domain_generators'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative '../../../../lib/stweak/adapters/checkpoint_store/in_memory'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'

# The stream and owner the examples create accounts for.
ACCOUNT_OWNER_TYPE = Stweak::Domain::Accounts::Account
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OTHER_ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000002')

# A run of AccountCreated events at sequences 1..count on one stream, so the
# handler's checkpoint path can be exercised at a hundred events.
def account_created_events(account_id, count)
  (1..count).map do |sequence|
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id, sequence: sequence, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5), account_id: account_id,
      username: "user-#{sequence}", password_hash: 'hash', name: "Name #{sequence}",
      email: "user#{sequence}@example.com"
    )
  end
end

# An account whose stream holds count events in the given store, rebuilt by
# reading the stream back.
def seeded_account(store, account_id, count)
  store.append(
    owner_type: Stweak::Domain::Accounts::Account,
    stream_id: account_id,
    expected_version: 0,
    events: account_created_events(account_id, count)
  )
  Stweak::Domain::Accounts::Account.replay(
    id: account_id,
    events: store.read_stream(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id)
  )
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
    username: username,
    password: password,
    name: name,
    email: email
  )
end

# The username is derived from the account id, so commands generated for the
# property can never collide on the username across iterations.
def command_with_unique_username(command)
  Stweak::Domain::Accounts::CreateAccount.new(
    account_id: command.account_id,
    username: "user-#{command.account_id}",
    password: command.password,
    name: command.name,
    email: command.email
  )
end

# The state an account exposes, for comparing a handled account with a
# replayed one.
def account_state(account)
  [account.created, account.username, account.name, account.password_hash]
end

def replay_account(account, store)
  events = store.read_stream(owner_type: Stweak::Domain::Accounts::Account, stream_id: account.id)
  Stweak::Domain::Accounts::Account.replay(id: account.id, events: events)
end

# A Usernames read kept current by the projection system: a minimal in-memory
# stand-in for the accounts table, so the handler's uniqueness check can be
# exercised without dragging the app-layer projector into the domain suite.
class RecordingUsernames < Stweak::Domain::Projection
  include Stweak::Ports::Usernames

  # rubocop:disable Lint/MissingSuper -- Projection defines no initialize for this to call
  def initialize
    @usernames = Set.new
  end
  # rubocop:enable Lint/MissingSuper

  def apply(event)
    case event
    when Stweak::Domain::Accounts::AccountCreated
      @usernames.add(event.username)
    end
  end

  def reset
    @usernames.clear
  end

  def include?(username)
    @usernames.include?(username)
  end
end

RSpec.describe Stweak::Domain::Accounts::CreateAccountHandler do
  include DomainPropertyGenerators

  subject(:handler) do
    described_class.new(
      event_store: store,
      password_hasher: password_hasher,
      checkpoint_store: checkpoint_store,
      usernames: usernames
    )
  end

  let(:subscription) { Stweak::Adapters::EventSubscription::InMemoryEventSubscription.new }
  let(:store) do
    Stweak::Adapters::EventStore::EncryptingEventStore.new(
      store: Stweak::Adapters::EventStore::InMemoryEventStore.new,
      cipher: Stweak::Adapters::Encryption::AesGcm.new,
      key_store: Stweak::Adapters::KeyStore::InMemoryKeyStore.new,
      subscription: subscription
    )
  end
  let(:password_hasher) { Stweak::Adapters::Security::Pbkdf2PasswordHasher.new(iterations: 1_000) }
  let(:checkpoint_store) { Stweak::Adapters::CheckpointStore::InMemoryCheckpointStore.new }
  let(:usernames) { RecordingUsernames.new }

  # Keep the usernames read current by registering it with a projection system
  # watching the store's subscription.
  before do
    Stweak::Domain::ProjectionSystem.new(
      event_store: store,
      projection_store: Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new,
      subscription: subscription
    ).register(usernames)
  end

  it 'creates the account' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.created).to be(true)
  end

  it 'appends the AccountCreated event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).length).to eq(1)
  end

  it 'stamps created_at on the appended event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    event = store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).first
    expect(event.created_at).to be_within(2).of(Time.now)
  end

  it 'stores the username in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).first.username).to eq('alice')
  end

  it 'stores the plaintext name in the event' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).first.name).to eq('Alice')
  end

  it 'stores a digest of the password' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.password_hash).to start_with('pbkdf2-sha256$')
  end

  it 'never stores the raw password' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account.password_hash).not_to eq('hunter2')
  end

  it 'stores the same digest in the event' do
    account = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    event = store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).first
    expect(event.password_hash).to eq(account.password_hash)
  end

  it 'rejects creating the same account twice' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'rejects a username another account already uses' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect { handler.handle(build_create_account_command(account_id: OTHER_ACCOUNT_ID)) }
      .to raise_error(Stweak::Domain::Accounts::UsernameTaken, /username alice is already in use/)
  end

  it 'allows a free username after other accounts exist' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    account = handler.handle(build_create_account_command(account_id: OTHER_ACCOUNT_ID, username: 'bob'))
    expect(account.created).to be(true)
  end

  it 'reports the account conflict, not a username collision, for a recreated account' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    handler.handle(build_create_account_command(account_id: OTHER_ACCOUNT_ID, username: 'bob'))
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID, username: 'bob')) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'returns the account for a retried create' do
    created = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    retried = handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(account_state(retried)).to eq(account_state(created))
  end

  it 'does not append a second event for a retried create' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(store.read_stream(owner_type: ACCOUNT_OWNER_TYPE, stream_id: ACCOUNT_ID).length).to eq(1)
  end

  it 'surfaces a concurrent append as AccountAlreadyExists' do
    allow(store).to receive(:append).and_raise(Stweak::Ports::ConcurrencyError)
    expect { handler.handle(build_create_account_command(account_id: ACCOUNT_ID)) }
      .to raise_error(Stweak::Domain::Accounts::AccountAlreadyExists)
  end

  it 'writes no checkpoint before a hundred events' do
    handler.handle(build_create_account_command(account_id: ACCOUNT_ID))
    expect(checkpoint_store.get(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID)).to be_nil
  end

  it 'persists a checkpoint after an append leaves the account at a boundary' do
    account = seeded_account(store, ACCOUNT_ID, 100)
    handler.send(:append, account)
    checkpoint = checkpoint_store.get(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID)
    expect(checkpoint.version).to eq(100)
  end

  it 'restores a stored checkpoint when loading an account' do
    checkpoint_store.put(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID, checkpoint: created_account_checkpoint)
    expect(handler.send(:load_account, ACCOUNT_ID).username).to eq('alice')
  end

  it 'reads only the tail after the checkpoint version when loading an account' do
    checkpoint_store.put(owner_type: ACCOUNT_OWNER_TYPE, owner_id: ACCOUNT_ID, checkpoint: created_account_checkpoint)
    allow(store).to receive(:read_stream).and_call_original
    handler.send(:load_account, ACCOUNT_ID)
    expect(store).to have_received(:read_stream).with(hash_including(after: 100))
  end

  it 'reads the whole stream when no checkpoint is stored' do
    allow(store).to receive(:read_stream).and_call_original
    handler.send(:load_account, ACCOUNT_ID)
    expect(store).to have_received(:read_stream).with(hash_including(after: 0))
  end

  it 'writes events that replay to the account it returned', :property do
    PropCheck.forall(create_account_command) do |command|
      handled = handler.handle(command_with_unique_username(command))
      expect(account_state(replay_account(handled, store))).to eq(account_state(handled))
    end
  end
end
