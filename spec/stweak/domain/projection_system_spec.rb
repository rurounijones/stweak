# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/projection_system'
require_relative '../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../lib/stweak/ports/event_store'
require_relative '../../../lib/stweak/ports/event_subscription'
require_relative '../../../lib/stweak/ports/projection_store'

# The stream the examples append to.
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OTHER_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000002')
OCCURRED_AT = Time.utc(2026, 1, 2, 3, 4, 5)
OWNER_TYPE = Stweak::Domain::Accounts::Account
CURSOR_KEY = "Stweak::Domain::Accounts::Account##{ACCOUNT_ID}".freeze
OTHER_CURSOR_KEY = "Stweak::Domain::Accounts::Account##{OTHER_ID}".freeze

# A projection that records the usernames it has seen and how many times it was
# reset, so the system's driving of it can be observed.
class RecordingProjection < Stweak::Domain::Projection
  attr_reader :usernames, :resets

  # rubocop:disable-next Lint/MissingSuper -- Projection defines no initialize for this to call
  def initialize
    @usernames = []
    @resets = 0
  end

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

# An AccountCreated event for the given username at the given sequence, on the
# given stream (the single account stream by default).
def created_event(sequence, username, stream_id = ACCOUNT_ID)
  Stweak::Domain::Accounts::AccountCreated.new(
    stream_id: stream_id, sequence: sequence, occurred_at: OCCURRED_AT,
    account_id: stream_id, username: username, password_hash: 'hash', name: username,
    email: "#{username}@example.com"
  )
end

# An AccountCreated event on a second, distinct stream.
def other_event(sequence, username)
  created_event(sequence, username, OTHER_ID)
end

# Make the event store's log the given events on the single account stream.
# The system keys its cursors off each event's own class, not the yielded
# owner type, so the yielded owner and id only have to be present.
def stub_log(event_store, *events)
  allow(event_store).to receive(:each_stream).and_yield(OWNER_TYPE, ACCOUNT_ID, events)
end

RSpec.describe Stweak::Domain::ProjectionSystem do
  subject(:system) do
    described_class.new(event_store: event_store, projection_store: projection_store, subscription: subscription)
  end

  let(:subscription) { instance_double(Stweak::Ports::EventSubscription) }
  let(:event_store) { instance_double(Stweak::Ports::EventStore) }
  let(:projection_store) { instance_double(Stweak::Ports::ProjectionStore) }
  let(:projection) { RecordingProjection.new }

  # Snapshots of every write, deep-copied at call time. The system persists the
  # same cursor hash it mutates in place, so a live reference would show every
  # write as the final state; copying pins what each write actually persisted.
  let(:writes) { [] }

  before do
    allow(subscription).to receive(:register)
    allow(projection_store).to receive(:read).and_return(nil)
    allow(projection_store).to receive(:write) { |projection_name:, cursors:| writes << [projection_name, cursors.dup] }
    allow(projection_store).to receive(:delete)
    allow(event_store).to receive(:each_stream) # an empty log by default
  end

  it 'registers itself as a listener on the subscription' do
    expect(subscription).to have_received(:register).with(listener: system)
  end

  it 'feeds a registered projection when events are appended' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(projection.include?('alice')).to be(true)
  end

  it 'does not feed a projection that is not registered' do
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(projection.include?('alice')).to be(false)
  end

  it 'registers over the existing log' do
    stub_log(event_store, created_event(1, 'alice'))
    system.register(projection)
    expect(projection.include?('alice')).to be(true)
  end

  it 'reads the stored cursors when registering' do
    system.register(projection)
    expect(projection_store).to have_received(:read).with(projection_name: projection.name)
  end

  it 'persists a projection when registering over the log' do
    stub_log(event_store, created_event(1, 'alice'))
    system.register(projection)
    expect(writes).to eq([[projection.name, { CURSOR_KEY => 1 }]])
  end

  it 'persists the cursors after an append' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(writes).to eq([[projection.name, { CURSOR_KEY => 1 }]])
  end

  it 'does not persist when registering over an empty log advances nothing' do
    system.register(projection)
    expect(writes).to eq([])
  end

  it 'does not persist when a re-delivered batch advances nothing' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(writes).to eq([[projection.name, { CURSOR_KEY => 1 }]])
  end

  it 'persists only the cursors that advanced, not the whole map' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [other_event(1, 'bob')])
    expect(writes.last).to eq([projection.name, { OTHER_CURSOR_KEY => 1 }])
  end

  it 'feeds a projection that registered over the log when more events arrive' do
    stub_log(event_store, created_event(1, 'alice'))
    system.register(projection)
    system.on_events_appended(events: [created_event(2, 'bob')])
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'does not re-apply events already consumed per the stored cursors' do
    allow(projection_store).to receive(:read).and_return(CURSOR_KEY => 1)
    stub_log(event_store, created_event(1, 'alice'))
    system.register(projection)
    expect(projection.usernames).to eq([])
  end

  it 'applies only the events after a stored cursor' do
    allow(projection_store).to receive(:read).and_return(CURSOR_KEY => 1)
    stub_log(event_store, created_event(1, 'alice'), created_event(2, 'bob'))
    system.register(projection)
    expect(projection.usernames).to eq(['bob'])
  end

  it 'skips a re-delivered batch' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(projection.usernames).to eq(['alice'])
  end

  it 'feeds the unconsumed tail of an overlapping batch' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [created_event(1, 'alice'), created_event(2, 'bob')])
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'applies a batch that starts after the last consumed event' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [created_event(2, 'bob')])
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'does not move a projection backwards on an older batch' do
    system.register(projection)
    system.on_events_appended(events: [created_event(1, 'alice')])
    system.on_events_appended(events: [created_event(2, 'bob')])
    system.on_events_appended(events: [created_event(1, 'alice')])
    expect(writes.last).to eq([projection.name, { CURSOR_KEY => 2 }])
  end

  it 'rebuild replays the whole log into a reset projection' do
    stub_log(event_store, created_event(1, 'alice'), created_event(2, 'bob'))
    system.rebuild(projection)
    expect(projection.usernames).to eq(%w[alice bob])
  end

  it 'rebuild resets the projection' do
    system.rebuild(projection)
    expect(projection.resets).to eq(1)
  end

  it 'rebuild discards the stored cursors' do
    system.rebuild(projection)
    expect(projection_store).to have_received(:delete).with(projection_name: projection.name)
  end
end
