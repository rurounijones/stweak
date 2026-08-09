# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/id'
require_relative '../../../support/event_subscription_examples'
require_relative '../../../support/versioned_event'

# Register a listener on `subscription`, publish `events`, and return the batch
# it was delivered. A top-level helper rather than a method in the describe
# block, which Sorbet forbids.
def deliver(subscription, events)
  listener = SubscribedListener.new
  subscription.register(listener: listener)
  subscription.publish(events: events)
  listener.deliveries.first
end

RSpec.describe Stweak::Adapters::EventSubscription::InMemoryEventSubscription do
  subject(:subscription) { described_class.new }

  let(:stream_id) { Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-000000000001') }

  let(:event) do
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: stream_id, sequence: 1, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5),
      account_id: Stweak::Domain::Accounts::AccountId.new(value: stream_id.to_s),
      username: 'alice', password_hash: 'hash', name: 'Alice', email: 'alice@example.com'
    )
  end

  let(:v1_event) do
    VersionedEvent.new(name: 'alice', stream_id: stream_id, sequence: 1,
                       occurred_at: Time.utc(2026, 1, 2, 3, 4, 5), version: 1)
  end

  it_behaves_like 'an event subscription'

  it 'delivers an event equal to the published one' do
    expect(deliver(subscription, [event]).first).to eq(event)
  end

  it 'delivers a reconstructed event, not the published object' do
    expect(deliver(subscription, [event]).first).not_to be(event)
  end

  it 'upcasts an older-version event before delivery' do
    delivered = deliver(subscription, [v1_event]).first
    expect(delivered).to have_attributes(name: 'alice', version: 2)
  end

  it 'does not rewrite the published event' do
    deliver(subscription, [v1_event])
    expect(v1_event.to_h).to include('full_name' => 'alice', 'version' => 1)
  end
end
