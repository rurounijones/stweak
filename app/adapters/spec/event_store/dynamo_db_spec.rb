# typed: false
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require_relative '../spec_helper'
require_relative '../../event_store/dynamo_db'
require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'

# The stream and owner the examples append to.
ACCOUNT_TYPE = Stweak::Domain::Accounts::Account
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OCCURRED_AT = Time.utc(2026, 1, 2, 3, 4, 5)

# A listener that records deliveries, so the store's publishing can be
# asserted.
class RecordingListener
  include Stweak::Ports::EventStoreListener

  attr_reader :deliveries

  def initialize
    @deliveries = []
  end

  def on_events_appended(events:)
    @deliveries << events
  end
end

# Drop the streams table so each example starts from an empty store. A missing
# table is a normal first run, not an error.
def drop_table(client)
  client.delete_table(table_name: 'stweak_streams')
rescue Aws::DynamoDB::Errors::ResourceNotFoundException
  nil
end

RSpec.describe App::Adapters::DynamoDBEventStore do
  subject(:store) do
    described_class.new(client: client, streams_table: 'stweak_streams', subscription: subscription)
  end

  # Dummy credentials: dynamodb-local needs none, but the SDK still wants a
  # credential source so it does not go looking for real ones. The endpoint is
  # the compose service name in the dev container, localhost in CI.
  let(:client) do
    Aws::DynamoDB::Client.new(
      endpoint: ENV.fetch('AWS_ENDPOINT_URL', 'http://localhost:8000'),
      region: 'us-east-1',
      credentials: Aws::Credentials.new('dummy', 'dummy')
    )
  end
  let(:subscription) { Stweak::Adapters::EventSubscription::InMemoryEventSubscription.new }

  let(:event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: ACCOUNT_ID, sequence: 1, occurred_at: OCCURRED_AT,
      account_id: ACCOUNT_ID, username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com'
    )
  end

  let(:second_event) { event.with('sequence' => 2, 'username' => 'bob', 'name' => 'Bob') }

  before { drop_table(client) }

  after { drop_table(client) }

  it 'appends and reads a stream back in order' do
    store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event, second_event])
    expect(store.read_stream(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID)).to eq([event, second_event])
  end

  it 'reads only the events after a given sequence' do
    store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event, second_event])
    expect(store.read_stream(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, after: 1)).to eq([second_event])
  end

  it 'refuses an append built on a stale version' do
    store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event])
    expect do
      store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [second_event])
    end.to raise_error(Stweak::Ports::ConcurrencyError)
  end

  it 'publishes an append to the subscription' do
    listener = RecordingListener.new
    subscription.register(listener: listener)
    store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event])
    expect(listener.deliveries).to eq([[event]])
  end

  it 'yields each stream with its owner and events in order' do
    store.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event, second_event])
    streams = []
    store.each_stream { |owner, id, events| streams << [owner, id, events] }
    expect(streams).to eq([[ACCOUNT_TYPE, ACCOUNT_ID, [event, second_event]]])
  end

  it 'yields nothing for an empty store' do
    streams = []
    store.each_stream { |owner, id, events| streams << [owner, id, events] }
    expect(streams).to eq([])
  end

  it 'builds over tables that already exist' do
    store
    expect { described_class.new(client: client, streams_table: 'stweak_streams') }.not_to raise_error
  end

  it 'does not publish when it has no subscription' do
    silent = described_class.new(client: client, streams_table: 'stweak_streams')
    expect { silent.append(owner_type: ACCOUNT_TYPE, stream_id: ACCOUNT_ID, expected_version: 0, events: [event]) }
      .not_to raise_error
  end
end
