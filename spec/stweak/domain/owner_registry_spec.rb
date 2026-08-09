# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/owner_registry'

RSpec.describe Stweak::Domain::OwnerRegistry do
  it 'maps an event to the aggregate class that owns its stream' do
    expect(described_class.owner_type_for(Stweak::Domain::Accounts::AccountCreated))
      .to eq(Stweak::Domain::Accounts::Account)
  end

  it 'registers an event class with its aggregate class' do
    described_class.register(event_class: Stweak::Domain::Event, aggregate_class: Stweak::Domain::Aggregate)
    expect(described_class.owner_type_for(Stweak::Domain::Event)).to eq(Stweak::Domain::Aggregate)
  end

  it 'raises for an event with no registered owner' do
    expect { described_class.owner_type_for(Class.new(Stweak::Domain::Event)) }.to raise_error(KeyError)
  end
end
