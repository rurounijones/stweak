# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/password_hash'
# A subclass, to pin that equality is by exact class: a hash and a subclass
# instance with the same value are unequal, and unequal both ways round.
class SubPasswordHash < Stweak::Domain::Accounts::PasswordHash; end

RSpec.describe Stweak::Domain::Accounts::PasswordHash do
  subject(:password_hash) { described_class.new(value: 'pbkdf2-sha256$1000$c2FsdA==$aGFzaA==') }

  it 'renders the digest plainly as a string, since a hash is not personal data' do
    expect(password_hash.to_s).to eq('pbkdf2-sha256$1000$c2FsdA==$aGFzaA==')
  end

  it 'renders its stored form as the plain digest' do
    expect(password_hash.to_stored).to eq('pbkdf2-sha256$1000$c2FsdA==$aGFzaA==')
  end

  it 'accepts a digest of any shape, being opaque to the algorithm' do
    expect(described_class.new(value: '$2b$12$abcdefg').to_s).to eq('$2b$12$abcdefg')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /password hash must not be empty/)
  end

  it 'is equal to a hash with the same digest' do
    expect(password_hash).to eq(described_class.new(value: 'pbkdf2-sha256$1000$c2FsdA==$aGFzaA=='))
  end

  it 'is not equal to a subclass with the same digest, symmetrically' do
    sub = SubPasswordHash.new(value: 'pbkdf2-sha256$1000$c2FsdA==$aGFzaA==')
    expect([password_hash == sub, sub == password_hash]).to all(be(false))
  end

  it 'is not equal to a hash with a different digest' do
    expect(password_hash == described_class.new(value: 'other')).to be(false)
  end

  it 'is not equal to a non-hash' do
    expect(password_hash == Object.new).to be(false)
  end

  it 'is eql to a hash with the same digest' do
    expect(password_hash.eql?(described_class.new(value: 'pbkdf2-sha256$1000$c2FsdA==$aGFzaA=='))).to be(true)
  end

  it 'hashes to the digest hash' do
    expect(password_hash.hash).to eq('pbkdf2-sha256$1000$c2FsdA==$aGFzaA=='.hash)
  end
end
