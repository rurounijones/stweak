# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/username'
# A subclass, to pin that equality is by exact class: a username and a subclass
# instance with the same value are unequal, and unequal both ways round.
class SubUsername < Stweak::Domain::Accounts::Username; end

RSpec.describe Stweak::Domain::Accounts::Username do
  subject(:username) { described_class.new(value: 'ada') }

  it 'holds the value' do
    expect(username.value).to eq('ada')
  end

  it 'renders the value as a string' do
    expect(username.to_s).to eq('ada')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /username must not be empty/)
  end

  it 'is equal to a username with the same value' do
    expect(username).to eq(described_class.new(value: 'ada'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubUsername.new(value: 'ada')
    expect([username == sub, sub == username]).to all(be(false))
  end

  it 'is not equal to a username with a different value' do
    expect(username == described_class.new(value: 'grace')).to be(false)
  end

  it 'is not equal to a non-username' do
    expect(username == Object.new).to be(false)
  end

  it 'is eql to a username with the same value' do
    expect(username.eql?(described_class.new(value: 'ada'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(username.hash).to eq('ada'.hash)
  end
end
