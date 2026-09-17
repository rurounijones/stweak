# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/password_plain_text'
# A subclass, to pin that equality is by exact class: a password and a subclass
# instance with the same secret are unequal, and unequal both ways round.
class SubPasswordPlainText < Stweak::Domain::Accounts::PasswordPlainText; end

RSpec.describe Stweak::Domain::Accounts::PasswordPlainText do
  subject(:password) { described_class.new(value: 'hunter2') }

  it 'exposes the real secret through the acknowledged plaintext reader' do
    expect(password.plaintext).to eq('hunter2')
  end

  it 'masks the secret when rendered as a string' do
    expect(password.to_s).to eq('*****')
  end

  it 'masks the secret when inspected' do
    expect(password.inspect).to eq('*****')
  end

  it 'masks with the fixed mask, not the secret' do
    expect(described_class::MASK).to eq('*****')
  end

  it 'accepts any non-empty secret, enforcing coherence rather than strength' do
    expect(described_class.new(value: 'a').plaintext).to eq('a')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /password must not be empty/)
  end

  it 'is equal to a password with the same secret' do
    expect(password).to eq(described_class.new(value: 'hunter2'))
  end

  it 'is not equal to a subclass with the same secret, symmetrically' do
    sub = SubPasswordPlainText.new(value: 'hunter2')
    expect([password == sub, sub == password]).to all(be(false))
  end

  it 'is not equal to a password with a different secret' do
    expect(password == described_class.new(value: 'other')).to be(false)
  end

  it 'is not equal to a non-password' do
    expect(password == Object.new).to be(false)
  end

  it 'is eql to a password with the same secret' do
    expect(password.eql?(described_class.new(value: 'hunter2'))).to be(true)
  end

  it 'hashes to the secret hash' do
    expect(password.hash).to eq('hunter2'.hash)
  end
end
