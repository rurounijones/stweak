# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../support/event_subscription_examples'

RSpec.describe Stweak::Adapters::EventSubscription::InMemoryEventSubscription do
  subject(:subscription) { described_class.new }

  it_behaves_like 'an event subscription'
end
