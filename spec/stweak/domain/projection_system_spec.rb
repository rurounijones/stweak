# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/projection_system'
require_relative '../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../lib/stweak/adapters/projection_store/in_memory'

# The stream the examples append to.
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OCCURRED_AT = Time.utc(2026, 1, 2, 3, 4, 5)
OWNER_TYPE = Stweak::Domain::Accounts::Account
CURSOR_KEY = "Stweak::Domain::Accounts::Account##{ACCOUNT_ID}".freeze

# A projection that records the usernames it has seen and how many times it was
# reset, so the system's driving of it can be observed.
class RecordingProjection < Stweak::Domain::Projection
  attr_reader :usernames, :resets

  # rubocop:disable Lint/MissingSuper -- Projection defines no initialize for this to call
  def initialize
    @usernames = []
    @resets = 0
  end
  # rubocop:enable Lint/MissingSuper

  def apply(event)
    @usernames << event.username
  end

  def reset
    @usernames = []
    @resets += 1
  end

  def include?(username)
    @usernames.include?(username)
  end
end

# An AccountCreated event for the given username at the given sequence.
def created_event(sequence, username)
  Stweak::Domain::Accounts::AccountCreated.new(
    stream_id: ACCOUNT_ID, sequence: sequence, occurred_at: OCCURRED_AT,
    account_id: ACCOUNT_ID, username: username, password_hash: 'hash', name: username,
    email: "#{username}@example.com"
  )
end

# Appends a single event to the store at the stream version its sequence
# implies.
def append_event(store, event)
  store.append(owner_type: OWNER_TYPE, stream_id: event.stream_id, expected_version: event.sequence - 1,
               events: [event])
end

RSpec.describe Stweak::Domain::ProjectionSystem do
  subject(:system) do
    described_class.new(event_store: store, projection_store: projection_store, subscription: subscription)
  end

  let(:subscription) { Stweak::Adapters::EventSubscription::InMemoryEventSubscription.new }
  let(:store) { Stweak::Adapters::EventStore::InMemoryEventStore.new(subscription: subscription) }
  let(:projection_store) { Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new }
  let(:projection) { RecordingProjection.new }
  let(:fresh_system) do
    described_class.new(event_store: store, projection_store: projection_store, subscription: subscription)
  end

  it 'feeds a registered projection when events are appended' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    expect(projection.include?('alice')).to be(true)
  end

  it 'does not feed a projection that is not registered' do
    append_event(store, created_event(1, 'alice'))
    expect(projection.include?('alice')).to be(false)
  end

  it 'registers over the existing log' do
    append_event(store, created_event(1, 'alice'))
    system.register(projection)
    expect(projection.include?('alice')).to be(true)
  end

  it 'persists a projection when registering over the log' do
    append_event(store, created_event(1, 'alice'))
    system.register(projection)
    expect(projection_store.read(projection_name: projection.name)).to eq(CURSOR_KEY => 1)
  end

  it 'persists the cursors after an append' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    expect(projection_store.read(projection_name: projection.name)).to eq(CURSOR_KEY => 1)
  end

  it 'feeds a projection that registered over the log when more events arrive' do
    append_event(store, created_event(1, 'alice'))
    system.register(projection)
    append_event(store, created_event(2, 'bob'))
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'does not re-apply consumed events on a fresh system' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    resumed = RecordingProjection.new.tap { |rebuilt| fresh_system.register(rebuilt) }
    expect(resumed.usernames).to eq([])
  end

  it 'resumes from the stored cursors' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    resumed = RecordingProjection.new.tap { |rebuilt| fresh_system.register(rebuilt) }
    expect(projection_store.read(projection_name: resumed.name)).to eq(CURSOR_KEY => 1)
  end

  it 'applies only the events after a stored cursor' do
    append_event(store, created_event(1, 'alice'))
    append_event(store, created_event(2, 'bob'))
    projection_store.write(projection_name: projection.name, cursors: { CURSOR_KEY => 1 })
    system.register(projection)
    expect(projection.usernames).to eq(['bob'])
  end

  it 'reads the stored cursors when registering' do
    allow(projection_store).to receive(:read).and_call_original
    system.register(projection)
    expect(projection_store).to have_received(:read).with(projection_name: projection.name)
  end

  it 'skips a re-delivered batch' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    subscription.publish(events: [created_event(1, 'alice')])
    expect(projection.usernames).to eq(['alice'])
  end

  it 'feeds the unconsumed tail of an overlapping batch' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    subscription.publish(events: [created_event(1, 'alice'), created_event(2, 'bob')])
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'skips the consumed prefix of a batch starting mid-log' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    subscription.publish(events: [created_event(2, 'bob')])
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'does not move a projection backwards on an older batch' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    append_event(store, created_event(2, 'bob'))
    subscription.publish(events: [created_event(1, 'alice')])
    expect(projection_store.read(projection_name: projection.name)).to eq(CURSOR_KEY => 2)
  end

  it 'stores a snapshot of the cursors, not a live reference' do
    system.register(projection)
    cursors = {}
    projection_store.write(projection_name: projection.name, cursors: cursors.dup)
    cursors[CURSOR_KEY] = 1
    expect(projection_store.read(projection_name: projection.name)).to eq({})
  end

  it 'rebuild replays the whole log into a reset projection' do
    system.register(projection)
    append_event(store, created_event(1, 'alice'))
    append_event(store, created_event(2, 'bob'))
    system.rebuild(projection)
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'rebuild resets the projection' do
    system.register(projection)
    system.rebuild(projection)
    expect(projection.resets).to eq(1)
  end

  it 'rebuild discards the stored cursors' do
    allow(projection_store).to receive(:delete)
    system.rebuild(projection)
    expect(projection_store).to have_received(:delete).with(projection_name: projection.name)
  end
end
