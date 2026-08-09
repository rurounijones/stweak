# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../support/property/generators'
RSpec.describe Stweak::Adapters::Encryption::AesGcm do
  include PropertyGenerators

  subject(:cipher) { described_class.new }

  let(:key) { cipher.generate_key }

  it 'round-trips plaintext' do
    encrypted = cipher.encrypt(plaintext: 'secret name', key: key)
    expect(cipher.decrypt(ciphertext: encrypted, key: key)).to eq('secret name')
  end

  it 'embeds nonce, tag and ciphertext' do
    parts = cipher.encrypt(plaintext: 'secret name', key: key).split('.')
    expect(parts.length).to eq(3)
  end

  it 'uses a fresh nonce for each encryption' do
    expect(cipher.encrypt(plaintext: 'secret name', key: key))
      .not_to eq(cipher.encrypt(plaintext: 'secret name', key: key))
  end

  it 'refuses to decrypt with the wrong key' do
    encrypted = cipher.encrypt(plaintext: 'secret name', key: key)
    expect { cipher.decrypt(ciphertext: encrypted, key: cipher.generate_key) }
      .to raise_error(ArgumentError, /decryption failed/)
  end

  it 'refuses a key of the wrong length when encrypting' do
    expect { cipher.encrypt(plaintext: 'x', key: 'short') }
      .to raise_error(ArgumentError, /32 bytes/)
  end

  it 'refuses a key of the wrong length when decrypting' do
    expect { cipher.decrypt(ciphertext: 'x', key: 'short') }
      .to raise_error(ArgumentError, /32 bytes/)
  end

  it 'refuses malformed ciphertext' do
    expect { cipher.decrypt(ciphertext: 'not-a-valid-ciphertext', key: key) }
      .to raise_error(ArgumentError, /malformed/)
  end

  it 'generates a 32-byte key' do
    expect(cipher.generate_key.bytesize).to eq(32)
  end

  it 'round-trips any plaintext under any key', :property do
    PropCheck.forall(string, aes_key) do |plaintext, key|
      expect(cipher.decrypt(ciphertext: cipher.encrypt(plaintext: plaintext, key: key), key: key))
        .to eq(plaintext)
    end
  end
end
