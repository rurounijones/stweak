# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../support/event_subscription_examples'
require_relative '../../../support/property/domain_generators'

# An in-memory store wired to a subscription with one recorded listener,
# returned with the listener.
def emitting_in_memory_store
  listener = SubscribedListener.new
  subscription = Stweak::Adapters::EventSubscription::InMemoryEventSubscription.new
  subscription.register(listener: listener)
  [Stweak::Adapters::EventStore::InMemoryEventStore.new(subscription: subscription), listener]
end

RSpec.describe Stweak::Adapters::EventStore::InMemoryEventStore do
  include DomainPropertyGenerators

  subject(:store) { described_class.new }

  let(:owner_type) { Stweak::Domain::Accounts::Account }
  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:other_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000002') }

  let(:event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id,
      sequence: 1,
      occurred_at: Time.utc(2026, 1, 2, 3, 4, 5),
      account_id: account_id,
      username: 'alice',
      password_hash: 'hash',
      name: 'Alice',
      email: 'alice@example.com'
    )
  end

  let(:second_event) { event.with('sequence' => 2) }

  it 'appends and reads back in order' do
    store.append(
      owner_type: owner_type, stream_id: account_id, expected_version: 0,
      events: [event, second_event]
    )
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id)).to eq([event, second_event])
  end

  it 'reads only the events after a given sequence' do
    store.append(
      owner_type: owner_type, stream_id: account_id, expected_version: 0,
      events: [event, second_event]
    )
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id, after: 1)).to eq([second_event])
  end

  it 'excludes the event at the given sequence' do
    store.append(
      owner_type: owner_type, stream_id: account_id, expected_version: 0,
      events: [event, second_event]
    )
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id, after: 2)).to eq([])
  end

  it 'returns an empty stream for an unknown id' do
    expect(store.read_stream(owner_type: owner_type, stream_id: other_id)).to eq([])
  end

  it 'keeps streams apart' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    expect(store.read_stream(owner_type: owner_type, stream_id: other_id)).to eq([])
  end

  it 'keeps the same stream id apart across owner classes' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    expect(store.read_stream(owner_type: Stweak::Domain::Aggregate, stream_id: account_id)).to eq([])
  end

  it 'refuses an append built on a stale version' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    expect do
      store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [second_event])
    end.to raise_error(Stweak::Ports::ConcurrencyError)
  end

  it 'accepts an append built on the current version' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 1, events: [second_event])
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id).length).to eq(2)
  end

  it 'refuses an out-of-sequence event' do
    expect do
      store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [second_event])
    end.to raise_error(Stweak::Ports::ConcurrencyError)
  end

  it 'returns a copy so callers cannot mutate stored events' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    result = store.read_stream(owner_type: owner_type, stream_id: account_id)
    result << second_event
    expect(store.read_stream(owner_type: owner_type, stream_id: account_id).length).to eq(1)
  end

  it 'yields each stream with its owner and events in order' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event, second_event])
    streams = []
    store.each_stream { |owner, id, events| streams << [owner, id, events] }
    expect(streams).to eq([[owner_type, account_id, [event, second_event]]])
  end

  it 'yields every stream' do
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    store.append(owner_type: owner_type, stream_id: other_id, expected_version: 0,
                 events: [event.with('stream_id' => other_id.to_s)])
    expect { |blk| store.each_stream(&blk) }.to yield_control.exactly(2).times
  end

  it 'yields nothing for an empty store' do
    streams = []
    store.each_stream { |owner, id, events| streams << [owner, id, events] }
    expect(streams).to eq([])
  end

  it 'publishes an append to a subscription' do
    emitting, listener = emitting_in_memory_store
    emitting.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    expect(listener.deliveries).to eq([[event]])
  end

  it 'publishes each append to a subscription' do
    emitting, listener = emitting_in_memory_store
    emitting.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    emitting.append(owner_type: owner_type, stream_id: account_id, expected_version: 1, events: [second_event])
    expect(listener.deliveries).to eq([[event], [second_event]])
  end

  it 'does not publish when it has no subscription' do
    listener = SubscribedListener.new
    store.append(owner_type: owner_type, stream_id: account_id, expected_version: 0, events: [event])
    expect(listener.deliveries).to eq([])
  end

  it 'preserves any sequence of events on a stream, in order', :property do
    PropCheck.forall(event_sequence) do |events|
      store.append(owner_type: owner_type, stream_id: events.first.stream_id, expected_version: 0, events: events)
      expect(store.read_stream(owner_type: owner_type, stream_id: events.first.stream_id)).to eq(events)
    end
  end
end
