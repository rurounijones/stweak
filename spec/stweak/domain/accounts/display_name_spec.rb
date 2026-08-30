# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/display_name'
# A subclass, to pin that equality is by exact class: a display name and a
# subclass instance with the same value are unequal, and unequal both ways round.
class SubDisplayName < Stweak::Domain::Accounts::DisplayName; end

RSpec.describe Stweak::Domain::Accounts::DisplayName do
  subject(:display_name) { described_class.new(value: 'Ada Lovelace') }

  it 'exposes the real name through the acknowledged pii reader' do
    expect(display_name.pii).to eq('Ada Lovelace')
  end

  it 'masks the name when rendered as a string' do
    expect(display_name.to_s).to eq('*****')
  end

  it 'masks the name when inspected' do
    expect(display_name.inspect).to eq('*****')
  end

  it 'renders its stored form as the plain value' do
    expect(display_name.to_stored).to eq('Ada Lovelace')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /name must not be empty/)
  end

  it 'is equal to a display name with the same value' do
    expect(display_name).to eq(described_class.new(value: 'Ada Lovelace'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubDisplayName.new(value: 'Ada Lovelace')
    expect([display_name == sub, sub == display_name]).to all(be(false))
  end

  it 'is not equal to a display name with a different value' do
    expect(display_name == described_class.new(value: 'Grace Hopper')).to be(false)
  end

  it 'is not equal to a non-display-name' do
    expect(display_name == Object.new).to be(false)
  end

  it 'is eql to a display name with the same value' do
    expect(display_name.eql?(described_class.new(value: 'Ada Lovelace'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(display_name.hash).to eq('Ada Lovelace'.hash)
  end
end
