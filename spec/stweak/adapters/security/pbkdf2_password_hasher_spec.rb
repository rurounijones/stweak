# typed: false
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'prop_check'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative '../../../support/property/generators'

# Concise builders for the password value objects the port speaks in.
def pw(value) = Stweak::Domain::Accounts::PasswordPlainText.new(value: value)
def ph(value) = Stweak::Domain::Accounts::PasswordHash.new(value: value)

RSpec.describe Stweak::Adapters::Security::Pbkdf2PasswordHasher do
  include PropertyGenerators

  subject(:hasher) { described_class.new(iterations: 1_000) }

  it 'uses the pbkdf2-sha256 algorithm' do
    expect(hasher.digest(password: pw('hunter2')).to_stored.split('$').first).to eq('pbkdf2-sha256')
  end

  it 'records the iteration count' do
    expect(hasher.digest(password: pw('hunter2')).to_stored.split('$')[1]).to eq('1000')
  end

  it 'defaults to the default iteration count when none is given' do
    expect(described_class.new.digest(password: pw('hunter2')).to_stored.split('$')[1])
      .to eq(described_class::DEFAULT_ITERATIONS.to_s)
  end

  it 'records a 16-byte salt' do
    salt = hasher.digest(password: pw('hunter2')).to_stored.split('$')[2]
    expect(Base64.strict_decode64(salt).bytesize).to eq(16)
  end

  it 'records a 32-byte digest' do
    digest = hasher.digest(password: pw('hunter2')).to_stored.split('$')[3]
    expect(Base64.strict_decode64(digest).bytesize).to eq(32)
  end

  it 'never returns the password itself' do
    expect(hasher.digest(password: pw('hunter2')).to_stored).not_to eq('hunter2')
  end

  it 'uses a fresh salt for each digest' do
    expect(hasher.digest(password: pw('hunter2'))).not_to eq(hasher.digest(password: pw('hunter2')))
  end

  it 'derives the recorded digest from the recorded parameters' do
    _, iterations, salt, digest = hasher.digest(password: pw('hunter2')).to_stored.split('$')
    expected = OpenSSL::PKCS5.pbkdf2_hmac('hunter2', Base64.strict_decode64(salt), iterations.to_i, 32, 'SHA256')
    expect(Base64.strict_decode64(digest)).to eq(expected)
  end

  it 'verifies the correct password' do
    digest = hasher.digest(password: pw('hunter2'))

    expect(hasher.verify(password: pw('hunter2'), digest: digest)).to be(true)
  end

  it 'rejects the wrong password' do
    digest = hasher.digest(password: pw('hunter2'))

    expect(hasher.verify(password: pw('wrong'), digest: digest)).to be(false)
  end

  it 'rejects malformed and incompatible digests' do
    aggregate_failures do
      expect(hasher.verify(password: pw('hunter2'), digest: ph('not-a-digest'))).to be(false)
      expect(hasher.verify(password: pw('hunter2'), digest: ph('bcrypt$1$salt$hash'))).to be(false)
      expect(hasher.verify(password: pw('hunter2'), digest: ph('pbkdf2-sha256$nope$c2FsdA==$aGFzaA=='))).to be(false)
    end
  end

  it 'rejects a non-positive iteration count' do
    salt = Base64.strict_encode64('0123456789abcdef')
    digest = Base64.strict_encode64('x' * 32)

    expect(hasher.verify(password: pw('hunter2'), digest: ph("pbkdf2-sha256$0$#{salt}$#{digest}"))).to be(false)
  end

  it 'rejects a genuine digest relabelled as another algorithm' do
    _, iterations, salt, digest = hasher.digest(password: pw('hunter2')).to_stored.split('$')

    expect(hasher.verify(password: pw('hunter2'), digest: ph("bcrypt$#{iterations}$#{salt}$#{digest}"))).to be(false)
  end

  it 'rejects a genuine digest carrying extra fields' do
    real = hasher.digest(password: pw('hunter2')).to_stored

    expect(hasher.verify(password: pw('hunter2'), digest: ph("#{real}$extra"))).to be(false)
  end

  it 'rejects a genuine digest whose hash is not 32 bytes' do
    salt = OpenSSL::Random.random_bytes(16)
    short = OpenSSL::PKCS5.pbkdf2_hmac('hunter2', salt, 1_000, 16, 'SHA256')
    digest = ph("pbkdf2-sha256$1000$#{Base64.strict_encode64(salt)}$#{Base64.strict_encode64(short)}")

    expect(hasher.verify(password: pw('hunter2'), digest: digest)).to be(false)
  end

  it 'rejects a stored digest that is not 32 bytes' do
    salt = Base64.strict_encode64('0123456789abcdef')
    short = Base64.strict_encode64('too-short')

    expect(hasher.verify(password: pw('hunter2'), digest: ph("pbkdf2-sha256$1000$#{salt}$#{short}"))).to be(false)
  end

  it 'rejects invalid base64' do
    expect(hasher.verify(password: pw('hunter2'), digest: ph('pbkdf2-sha256$1000$%%%$%%%'))).to be(false)
  end

  it 'verifies a digest produced by another instance' do
    digest = described_class.new(iterations: 1_000).digest(password: pw('hunter2'))

    expect(hasher.verify(password: pw('hunter2'), digest: digest)).to be(true)
  end

  it 'produces a self-describing digest for any password', :property do
    PropCheck.forall(nonempty_string) do |password|
      expect(hasher.digest(password: pw(password)).to_stored)
        .to match(%r{\Apbkdf2-sha256\$\d+\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+\z})
    end
  end

  it 'uses a fresh salt for any password', :property do
    PropCheck.forall(nonempty_string) do |password|
      expect(hasher.digest(password: pw(password))).not_to eq(hasher.digest(password: pw(password)))
    end
  end

  it 'verifies any password against its own digest', :property do
    PropCheck.forall(nonempty_string) do |password|
      expect(hasher.verify(password: pw(password), digest: hasher.digest(password: pw(password)))).to be(true)
    end
  end

  it 'rejects any password other than the one it hashed', :property do
    PropCheck.forall(nonempty_string, nonempty_string) do |a, b|
      next if b == a

      expect(hasher.verify(password: pw(b), digest: hasher.digest(password: pw(a)))).to be(false)
    end
  end
end
