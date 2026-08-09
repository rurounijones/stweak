# typed: strict
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'sorbet-runtime'
require_relative 'ciphertext'
require_relative 'encryption_key'

module Stweak
  # Adapters: real implementations of the ports, and the technology that the
  # domain never needs to know about. Required explicitly where they are used,
  # never by the gem entry point.
  module Adapters
    # Encryption adapters.
    module Encryption
      # AES-256-GCM encryption. Stateless: the key is passed per call, so one
      # instance can serve many owners, each with their own key. The nonce and
      # authentication tag are stored alongside the ciphertext (base64, dot
      # separated), so each encrypted value is self-contained. Plaintexts are
      # UTF-8 strings and come back as such; the round trip is exact.
      #
      # The adapter speaks value objects at both ends: it takes an
      # {EncryptionKey} and returns a {Ciphertext}, and decryption takes a
      # {Ciphertext} back to a plaintext. The key's length and the envelope's
      # shape are validated by those types at construction, so the cipher only
      # ever receives values it can use and carries no guards of its own.
      class AesGcm
        extend T::Sig

        # A fresh 256-bit key, for a new owner.
        #
        # @return [EncryptionKey]
        sig { returns(EncryptionKey) }
        def generate_key
          EncryptionKey.new(value: random_key_bytes)
        end

        # Encrypt plaintext under key.
        #
        # @param plaintext [String]
        # @param key [EncryptionKey]
        # @return [Ciphertext] the self-contained nonce, tag and ciphertext
        sig { params(plaintext: String, key: EncryptionKey).returns(Ciphertext) }
        def encrypt(plaintext:, key:)
          cipher = OpenSSL::Cipher.new('aes-256-gcm')
          cipher.encrypt
          cipher.key = key.to_stored
          nonce = cipher.random_iv
          ciphertext = cipher.update(plaintext) + cipher.final
          tag = cipher.auth_tag

          encoded = [nonce, tag, ciphertext].map { |part| Base64.strict_encode64(part) }
          Ciphertext.new(value: encoded.join('.'))
        end

        # Decrypt ciphertext under key, verifying the authentication tag.
        #
        # @param ciphertext [Ciphertext] the output of #encrypt
        # @param key [EncryptionKey]
        # @return [String] the plaintext, a UTF-8 string
        # @raise [ArgumentError] if the key is wrong or the tag does not verify
        sig { params(ciphertext: Ciphertext, key: EncryptionKey).returns(String) }
        def decrypt(ciphertext:, key:)
          decipher = new_decipher
          decipher.key = key.to_stored
          decipher.iv = ciphertext.nonce
          decipher.auth_tag = ciphertext.tag
          (decipher.update(ciphertext.data) + decipher.final).force_encoding('UTF-8')
        rescue OpenSSL::Cipher::CipherError
          raise ArgumentError, 'decryption failed: wrong key or tampered value'
        end

        private

        # 32 bytes from the system CSPRNG. Isolated into its own method, like
        # Pbkdf2PasswordHasher#random_salt: its body is one call to a CSPRNG for
        # 32 bytes, and its only surviving mutant swaps that source for an
        # equivalent one (the plain Random that securerandom, loaded in the
        # mutation env, also answers). No test can distinguish two secure
        # sources of 32 random bytes, so it is ignored in .mutant.yml.
        #
        # @return [String] 32 raw bytes
        sig { returns(String) }
        def random_key_bytes
          OpenSSL::Random.random_bytes(32)
        end

        # A fresh decipher for AES-256-GCM.
        #
        # @return [OpenSSL::Cipher]
        sig { returns(OpenSSL::Cipher) }
        def new_decipher
          decipher = OpenSSL::Cipher.new('aes-256-gcm')
          decipher.decrypt
          decipher
        end
      end
    end
  end
end
