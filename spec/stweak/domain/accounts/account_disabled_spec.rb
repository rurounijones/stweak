# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/account_disabled'
require_relative '../../../../lib/stweak/domain/owner_registry'

RSpec.describe Stweak::Domain::Accounts::AccountDisabled do
  subject(:event) do
    described_class.new(stream_id: account_id, sequence: 2, occurred_at: occurred_at, created_at: created_at)
  end

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:occurred_at) { Time.utc(2026, 1, 2, 3, 4, 5) }
  let(:created_at) { Time.utc(2026, 1, 2, 3, 4, 9) }

  it 'reports its type and version' do
    expect([event.type, event.version]).to eq(['AccountDisabled', 1])
  end

  it 'has no PII fields' do
    expect(described_class.pii_fields).to eq([])
  end

  it 'does not shred the owner key' do
    expect(described_class.shreds_owner_key?).to be(false)
  end

  it 'round-trips through its serialized form' do
    expect(described_class.from_h(event.to_h)).to eq(event)
  end

  it 'maps to Account' do
    expect(Stweak::Domain::OwnerRegistry.owner_type_for(described_class))
      .to eq(Stweak::Domain::Accounts::Account)
  end
end
