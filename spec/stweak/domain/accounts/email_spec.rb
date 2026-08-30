# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/email'
# A subclass, to pin that equality is by exact class: an email and a subclass
# instance with the same value are unequal, and unequal both ways round.
class SubEmail < Stweak::Domain::Accounts::Email; end

RSpec.describe Stweak::Domain::Accounts::Email do
  subject(:email) { described_class.new(value: 'ada@example.com') }

  it 'exposes the real address through the acknowledged pii reader' do
    expect(email.pii).to eq('ada@example.com')
  end

  it 'masks the address when rendered as a string' do
    expect(email.to_s).to eq('*****')
  end

  it 'masks the address when inspected' do
    expect(email.inspect).to eq('*****')
  end

  it 'renders its stored form as the plain value' do
    expect(email.to_stored).to eq('ada@example.com')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /email must not be empty/)
  end

  it 'is equal to an email with the same value' do
    expect(email).to eq(described_class.new(value: 'ada@example.com'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubEmail.new(value: 'ada@example.com')
    expect([email == sub, sub == email]).to all(be(false))
  end

  it 'is not equal to an email with a different value' do
    expect(email == described_class.new(value: 'grace@example.com')).to be(false)
  end

  it 'is not equal to a non-email' do
    expect(email == Object.new).to be(false)
  end

  it 'is eql to an email with the same value' do
    expect(email.eql?(described_class.new(value: 'ada@example.com'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(email.hash).to eq('ada@example.com'.hash)
  end
end
