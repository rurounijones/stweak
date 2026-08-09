# typed: false
# frozen_string_literal: true

require 'aws-sdk-sqs'
require_relative '../spec_helper'
require_relative '../../event_subscription/elastic_mq'

# The stream the examples publish events for.
ACCOUNT_ID = Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
OCCURRED_AT = Time.utc(2026, 1, 2, 3, 4, 5)

# A listener that records deliveries, for asserting the subscription delivers.
class QueuedListener
  include Stweak::Ports::EventStoreListener

  attr_reader :deliveries

  def initialize
    @deliveries = []
  end

  def on_events_appended(events:)
    @deliveries << events
  end
end

# Wait until the block is truthy or thirty seconds pass, since the
# subscription delivers asynchronously through the queue and the poller is
# slowest under suite load.
def eventually
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
  loop do
    return if yield

    raise 'timed out waiting for the queue' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    sleep 0.02
  end
end

RSpec.describe App::Adapters::ElasticMqSubscription do
  subject(:subscription) do
    described_class.new(sqs: sqs, queue_name: queue_name, poll_interval: 0.01)
  end

  # Dummy credentials: ElasticMQ needs none, but the SDK still wants a
  # credential source so it does not go looking for real ones. The endpoint is
  # the compose service name in the dev container, localhost in CI.
  let(:sqs) do
    Aws::SQS::Client.new(
      endpoint: ENV.fetch('ELASTICMQ_URL', 'http://localhost:9324'),
      region: 'us-east-1',
      credentials: Aws::Credentials.new('dummy', 'dummy')
    )
  end
  let(:queue_name) { "stweak-test-#{object_id}" }

  let(:event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: ACCOUNT_ID, sequence: 1, occurred_at: OCCURRED_AT,
      account_id: ACCOUNT_ID, username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com'
    )
  end

  after { subscription.stop }

  # Delivery is at-least-once: the poller may deliver a batch more than once
  # if its delete races, so the assertions check the batch arrived, not that it
  # arrived exactly once.
  it 'delivers a published batch to a registered listener' do
    listener = QueuedListener.new
    subscription.register(listener: listener)
    subscription.publish(events: [event])
    eventually { listener.deliveries.any? }
    expect(listener.deliveries).to include([event])
  end

  it 'delivers to every registered listener' do
    listeners = Array.new(2) { QueuedListener.new }
    listeners.each { |listener| subscription.register(listener: listener) }
    subscription.publish(events: [event])
    eventually { listeners.all? { |listener| listener.deliveries.any? } }
    expect(listeners.map(&:deliveries)).to all(include([event]))
  end

  it 'survives a malformed message' do
    listener = QueuedListener.new.tap { |l| subscription.register(listener: l) }
    sqs.send_message(queue_url: subscription.queue_url, message_body: 'not json')
    subscription.publish(events: [event])
    eventually { listener.deliveries.any? }
    expect(listener.deliveries).to include([event])
  end

  # The malformed-message case exercises the per-message rescue inside a poll;
  # this drives the loop's own rescue, where the queue read itself fails: a
  # transient error must not kill the poller.
  context 'when a queue read raises' do
    # Fail the first read, then fall through to the real client, so the poller
    # meets an error from the queue itself and must recover rather than die.
    before do
      read = sqs.method(:receive_message)
      raised = false
      allow(sqs).to receive(:receive_message) do |*args, **kwargs|
        next read.call(*args, **kwargs) if raised

        raised = true
        raise 'transient queue read failure'
      end
    end

    it 'keeps polling and still delivers' do
      listener = QueuedListener.new.tap { |l| subscription.register(listener: l) }
      subscription.publish(events: [event])
      eventually { listener.deliveries.any? }
      expect(listener.deliveries).to include([event])
    end
  end
end
