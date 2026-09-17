# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../security/bcrypt_password_hasher'

# Concise builders for the password value objects the port speaks in.
def pw(value) = Stweak::Domain::Accounts::PasswordPlainText.new(value: value)
def ph(value) = Stweak::Domain::Accounts::PasswordHash.new(value: value)

RSpec.describe App::Adapters::BcryptPasswordHasher do
  subject(:hasher) { described_class.new }

  it 'produces a bcrypt digest' do
    expect(hasher.digest(password: pw('hunter2')).to_stored).to start_with('$2')
  end

  it 'does not store the raw password' do
    expect(hasher.digest(password: pw('hunter2')).to_stored).not_to eq('hunter2')
  end

  it 'produces a different digest for a different password' do
    expect(hasher.digest(password: pw('hunter2'))).not_to eq(hasher.digest(password: pw('password')))
  end

  it 'verifies the correct password' do
    digest = hasher.digest(password: pw('hunter2'))

    expect(hasher.verify(password: pw('hunter2'), digest: digest)).to be(true)
  end

  it 'rejects the wrong password' do
    digest = hasher.digest(password: pw('hunter2'))

    expect(hasher.verify(password: pw('wrong'), digest: digest)).to be(false)
  end

  it 'rejects an invalid digest' do
    expect(hasher.verify(password: pw('hunter2'), digest: ph('not-a-bcrypt-digest'))).to be(false)
  end
end
