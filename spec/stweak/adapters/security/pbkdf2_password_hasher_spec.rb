# typed: false
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'prop_check'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative '../../../support/property/generators'
RSpec.describe Stweak::Adapters::Security::Pbkdf2PasswordHasher do
  include PropertyGenerators

  subject(:hasher) { described_class.new(iterations: 1_000) }

  it 'uses the pbkdf2-sha256 algorithm' do
    expect(hasher.digest(password: 'hunter2').split('$').first).to eq('pbkdf2-sha256')
  end

  it 'records the iteration count' do
    expect(hasher.digest(password: 'hunter2').split('$')[1]).to eq('1000')
  end

  it 'records a 16-byte salt' do
    salt = hasher.digest(password: 'hunter2').split('$')[2]
    expect(Base64.strict_decode64(salt).bytesize).to eq(16)
  end

  it 'records a 32-byte digest' do
    digest = hasher.digest(password: 'hunter2').split('$')[3]
    expect(Base64.strict_decode64(digest).bytesize).to eq(32)
  end

  it 'never returns the password itself' do
    expect(hasher.digest(password: 'hunter2')).not_to eq('hunter2')
  end

  it 'uses a fresh salt for each digest' do
    expect(hasher.digest(password: 'hunter2')).not_to eq(hasher.digest(password: 'hunter2'))
  end

  it 'derives the recorded digest from the recorded parameters' do
    _, iterations, salt, digest = hasher.digest(password: 'hunter2').split('$')
    expected = OpenSSL::PKCS5.pbkdf2_hmac('hunter2', Base64.strict_decode64(salt), iterations.to_i, 32, 'SHA256')
    expect(Base64.strict_decode64(digest)).to eq(expected)
  end

  it 'verifies the correct password' do
    digest = hasher.digest(password: 'hunter2')

    expect(hasher.verify(password: 'hunter2', digest: digest)).to be(true)
  end

  it 'rejects the wrong password' do
    digest = hasher.digest(password: 'hunter2')

    expect(hasher.verify(password: 'wrong', digest: digest)).to be(false)
  end

  it 'rejects malformed and incompatible digests' do
    aggregate_failures do
      expect(hasher.verify(password: 'hunter2', digest: 'not-a-digest')).to be(false)
      expect(hasher.verify(password: 'hunter2', digest: 'bcrypt$1$salt$hash')).to be(false)
      expect(hasher.verify(password: 'hunter2', digest: 'pbkdf2-sha256$nope$c2FsdA==$aGFzaA==')).to be(false)
    end
  end

  it 'rejects a non-positive iteration count' do
    salt = Base64.strict_encode64('0123456789abcdef')
    digest = Base64.strict_encode64('x' * 32)

    expect(hasher.verify(password: 'hunter2', digest: "pbkdf2-sha256$0$#{salt}$#{digest}")).to be(false)
  end

  it 'rejects a stored digest that is not 32 bytes' do
    salt = Base64.strict_encode64('0123456789abcdef')
    short = Base64.strict_encode64('too-short')

    expect(hasher.verify(password: 'hunter2', digest: "pbkdf2-sha256$1000$#{salt}$#{short}")).to be(false)
  end

  it 'rejects invalid base64' do
    expect(hasher.verify(password: 'hunter2', digest: 'pbkdf2-sha256$1000$%%%$%%%')).to be(false)
  end

  it 'verifies a digest produced by another instance' do
    digest = described_class.new(iterations: 1_000).digest(password: 'hunter2')

    expect(hasher.verify(password: 'hunter2', digest: digest)).to be(true)
  end

  it 'produces a self-describing digest for any password', :property do
    PropCheck.forall(string) do |password|
      expect(hasher.digest(password: password))
        .to match(%r{\Apbkdf2-sha256\$\d+\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+\z})
    end
  end

  it 'uses a fresh salt for any password', :property do
    PropCheck.forall(string) do |password|
      expect(hasher.digest(password: password)).not_to eq(hasher.digest(password: password))
    end
  end
end
