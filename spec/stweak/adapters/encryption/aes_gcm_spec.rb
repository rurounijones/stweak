# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/adapters/encryption/ciphertext'
require_relative '../../../../lib/stweak/adapters/encryption/encryption_key'
require_relative '../../../support/property/generators'

# A ciphertext whose nonce and tag come from one encryption and whose data comes
# from another, so the tag cannot verify.
def tampered_ciphertext(first, second)
  nonce, tag, = first.to_stored.split('.')
  _, _, data = second.to_stored.split('.')
  Stweak::Adapters::Encryption::Ciphertext.new(value: "#{nonce}.#{tag}.#{data}")
end

RSpec.describe Stweak::Adapters::Encryption::AesGcm do
  include PropertyGenerators

  subject(:cipher) { described_class.new }

  let(:key) { cipher.generate_key }

  it 'round-trips plaintext' do
    encrypted = cipher.encrypt(plaintext: 'secret name', key: key)
    expect(cipher.decrypt(ciphertext: encrypted, key: key)).to eq('secret name')
  end

  it 'returns a ciphertext value object' do
    expect(cipher.encrypt(plaintext: 'secret name', key: key))
      .to be_a(Stweak::Adapters::Encryption::Ciphertext)
  end

  it 'embeds nonce, tag and ciphertext' do
    parts = cipher.encrypt(plaintext: 'secret name', key: key).to_stored.split('.')
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

  it 'refuses to decrypt a tampered ciphertext' do
    first = cipher.encrypt(plaintext: 'secret name', key: key)
    second = cipher.encrypt(plaintext: 'other secret', key: key)

    expect { cipher.decrypt(ciphertext: tampered_ciphertext(first, second), key: key) }
      .to raise_error(ArgumentError, /decryption failed/)
  end

  it 'round-trips an empty plaintext' do
    encrypted = cipher.encrypt(plaintext: '', key: key)
    expect(cipher.decrypt(ciphertext: encrypted, key: key)).to eq('')
  end

  it 'generates a 32-byte key' do
    expect(cipher.generate_key.to_stored.bytesize).to eq(32)
  end

  it 'round-trips any plaintext under any key', :property do
    PropCheck.forall(string, aes_key) do |plaintext, raw_key|
      key = Stweak::Adapters::Encryption::EncryptionKey.new(value: raw_key)
      expect(cipher.decrypt(ciphertext: cipher.encrypt(plaintext: plaintext, key: key), key: key))
        .to eq(plaintext)
    end
  end
end
