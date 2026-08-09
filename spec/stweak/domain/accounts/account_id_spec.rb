# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/account_id'
# A subclass, to pin that equality is by value and not by exact class.
class OtherAccountId < Stweak::Domain::Accounts::AccountId; end

RSpec.describe Stweak::Domain::Accounts::AccountId do
  subject(:account_id) { described_class.new(value: uuid) }

  let(:uuid) { '00000000-0000-4000-8000-000000000001' }

  it 'holds the value' do
    expect(account_id.value).to eq(uuid)
  end

  it 'renders the value as a string' do
    expect(account_id.to_s).to eq(uuid)
  end

  it 'rejects a non-UUID, naming the bad value in quotes' do
    expect { described_class.new(value: 'not-a-uuid') }
      .to raise_error(Stweak::Domain::ValidationError, /"not-a-uuid"/)
  end

  it 'rejects a value that is not valid UTF-8' do
    expect { described_class.new(value: "\xFF") }
      .to raise_error(Stweak::Domain::ValidationError, /UUID/)
  end

  it 'is equal to an id with the same value' do
    other = described_class.new(value: uuid)
    expect(account_id).to eq(other)
  end

  it 'is eql to an id with the same value' do
    other = described_class.new(value: uuid)
    expect(account_id.eql?(other)).to be(true)
  end

  it 'hashes to the value hash' do
    expect(account_id.hash).to eq(uuid.hash)
  end

  it 'is equal to a subclass with the same value' do
    other = OtherAccountId.new(value: uuid)
    expect(account_id).to eq(other)
  end

  it 'is not equal to an id with a different value' do
    other = described_class.new(value: '00000000-0000-4000-8000-000000000002')
    expect(account_id == other).to be(false)
  end

  it 'is not equal to a non-account-id' do
    expect(account_id == Object.new).to be(false)
  end

  it 'is not equal to a generic id with the same value' do
    expect(account_id == Stweak::Domain::Id.new(value: uuid)).to be(false)
  end
end
