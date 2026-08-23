# typed: false
# frozen_string_literal: true

# These doubles deliberately share one file: they are private fixtures for the
# instrumentation contract, not production collaborators.
# rubocop:disable Style/Documentation
# rubocop:disable RSpec/ExampleLength

require 'aws-sdk-dynamodb'
require 'aws-sdk-sqs'
require 'opentelemetry'
require_relative 'spec_helper'
require_relative '../checkpoint_store/redis'
require_relative '../key_store/redis'
require_relative '../../observability/adapters'
require_relative '../../../lib/stweak/domain/checkpoint'
require_relative '../../../lib/stweak/domain/accounts/account_id'
require_relative '../../../lib/stweak/domain/accounts/account'
require_relative '../../../lib/stweak/adapters/encryption/aes_gcm'
require 'redis'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/ReceiveMessages
# rubocop:disable Layout/LineLength

module AdapterObservabilityDoubles
  class RecordingSpan
    attr_reader :attributes

    def initialize
      @attributes = {}
    end

    def set_attribute(key, value)
      @attributes[key] = value
    end
  end

  # Subclasses the real tracer so the adapters' runtime T.let type checks accept
  # it, while recording every span opened through it.
  class RecordingTracer < OpenTelemetry::Trace::Tracer
    attr_reader :spans

    def initialize
      super
      @spans = []
    end

    def in_span(name, attributes: {}, **)
      span = RecordingSpan.new
      @spans << { name: name, attributes: attributes || {}, span: span }
      yield span
    end
  end

  class RecordingProvider
    def initialize(tracer)
      @tracer = tracer
    end

    def tracer(_name)
      @tracer
    end
  end
end

RSpec.describe App::Observability::Adapters do
  subject(:tracer) { AdapterObservabilityDoubles::RecordingTracer.new }

  let(:provider) { AdapterObservabilityDoubles::RecordingProvider.new(tracer) }
  let(:dynamo) { Aws::DynamoDB::Client.new(stub_responses: true, region: 'us-east-1') }
  let(:sqs) do
    client = Aws::SQS::Client.new(stub_responses: true, region: 'us-east-1', endpoint: 'http://localhost:9324')
    client.stub_responses(:create_queue, queue_url: 'http://localhost:9324/000000000000/stweak-events')
    client
  end
  let(:account_id) do
    Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
  end

  before do
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(provider)
    described_class.install
  end

  it 'installs wrappers only once' do
    described_class.install

    aggregate_failures do
      expect(App::Adapters::DynamoDBEventStore.ancestors.count(
               App::Observability::Adapters::EventStoreTracing
             )).to eq(1)
      expect(App::Adapters::ElasticMqSubscription.ancestors.count(
               App::Observability::Adapters::EventSubscriptionTracing
             )).to eq(1)
    end
  end

  it 'traces the event store boot, append, read, and scan' do
    store = App::Adapters::DynamoDBEventStore.new(client: dynamo, streams_table: 'stweak_streams')
    store.append(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id, expected_version: 0, events: [])
    store.read_stream(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id)
    store.each_stream { |owner, _id, _events| owner }

    aggregate_failures do
      expect(tracer.spans.map { |span| span[:name] }).to include(
        'eventstore.ensure_tables',
        'eventstore.append', 'eventstore.read_stream', 'eventstore.each_stream'
      )
      expect(tracer.spans.find { |span| span[:name] == 'eventstore.append' }[:attributes]).to include(
        'stweak.aggregate' => 'Stweak::Domain::Accounts::Account',
        'stweak.stream_id' => account_id.to_s,
        'stweak.event_count' => 0
      )
      expect(tracer.spans.find { |span| span[:name] == 'eventstore.ensure_tables' }[:attributes]).to eq(
        'stweak.table' => 'stweak_streams',
        'code.function' => 'App::Adapters::DynamoDBEventStore#create_tables'
      )
    end
  end

  it 'traces the subscription boot and publish' do
    subscription = App::Adapters::ElasticMqSubscription.new(sqs: sqs, queue_name: 'stweak-events', poll_interval: 60.0)
    subscription.publish(events: [])
    subscription.stop

    aggregate_failures do
      expect(tracer.spans.map { |span| span[:name] }).to include('subscription.ensure_queue', 'subscription.publish')
      expect(tracer.spans.find { |span| span[:name] == 'subscription.ensure_queue' }[:attributes]).to eq(
        'stweak.queue' => 'stweak-events',
        'code.function' => 'App::Adapters::ElasticMqSubscription#ensure_queue'
      )
      expect(tracer.spans.find { |span| span[:name] == 'subscription.publish' }[:attributes]).to eq(
        'stweak.event_count' => 0,
        'code.function' => 'App::Adapters::ElasticMqSubscription#publish'
      )
    end
  end

  it 'traces every Redis key-store operation semantically' do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
    store = App::Adapters::RedisKeyStore.new(redis: redis)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:set).and_return('OK')
    allow(redis).to receive(:del).and_return(1)

    store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
    store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id, key: 'secret')
    store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)

    expect(tracer.spans.map { |span| span[:name] }).to include('keystore.get', 'keystore.put', 'keystore.delete')
    expect(tracer.spans.select { |span| span[:name].start_with?('keystore.') }.map { |span| span[:attributes] }).to all(
      include('stweak.owner_type' => 'Stweak::Domain::Accounts::Account', 'stweak.owner_id' => account_id.to_s)
    )
  end

  it 'traces every Redis checkpoint operation semantically' do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
    store = App::Adapters::RedisCheckpointStore.new(redis: redis)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:set).and_return('OK')
    allow(redis).to receive(:del).and_return(1)
    checkpoint = Stweak::Domain::Checkpoint.new(state: { 'created' => true }, version: 1)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:set).and_return('OK')
    allow(redis).to receive(:del).and_return(1)

    store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
    store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id, checkpoint: checkpoint)
    store.delete(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)

    expect(tracer.spans.map { |span| span[:name] }).to include('checkpoint.get', 'checkpoint.put', 'checkpoint.delete')
    expect(tracer.spans.select { |span| span[:name].start_with?('checkpoint.') }.map { |span| span[:attributes] }).to all(
      include('stweak.owner_type' => 'Stweak::Domain::Accounts::Account', 'stweak.owner_id' => account_id.to_s)
    )
  end
end

# rubocop:enable Layout/LineLength
# rubocop:enable RSpec/ReceiveMessages
# rubocop:enable RSpec/MultipleExpectations
# rubocop:enable RSpec/ExampleLength
# rubocop:enable Style/Documentation
