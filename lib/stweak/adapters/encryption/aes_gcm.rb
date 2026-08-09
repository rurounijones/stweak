# typed: strict
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'sorbet-runtime'

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
      class AesGcm
        extend T::Sig

        # A fresh 256-bit key, for a new owner.
        #
        # @return [String] 32 raw bytes
        sig { returns(String) }
        def generate_key
          OpenSSL::Random.random_bytes(32)
        end

        # Encrypt plaintext under key.
        #
        # @param plaintext [String]
        # @param key [String] 32 raw bytes
        # @return [String] base64 nonce, tag and ciphertext, dot separated
        # @raise [ArgumentError] if key is not 32 bytes
        sig { params(plaintext: String, key: String).returns(String) }
        def encrypt(plaintext:, key:)
          raise ArgumentError, 'key must be 32 bytes' unless key.bytesize == 32

          cipher = OpenSSL::Cipher.new('aes-256-gcm')
          cipher.encrypt
          cipher.key = key
          nonce = cipher.random_iv
          cipher.iv = nonce
          ciphertext = cipher.update(plaintext) + cipher.final
          tag = cipher.auth_tag

          "#{Base64.strict_encode64(nonce)}.#{Base64.strict_encode64(tag)}.#{Base64.strict_encode64(ciphertext)}"
        end

        # Decrypt ciphertext under key, verifying the authentication tag.
        #
        # @param ciphertext [String] the output of #encrypt
        # @param key [String] 32 raw bytes
        # @return [String] the plaintext, a UTF-8 string
        # @raise [ArgumentError] if the key is wrong, the value is malformed, or
        #   the tag does not verify
        sig { params(ciphertext: String, key: String).returns(String) }
        def decrypt(ciphertext:, key:)
          raise ArgumentError, 'key must be 32 bytes' unless key.bytesize == 32

          nonce, tag, data = split_ciphertext(ciphertext)
          decipher = new_decipher
          decipher.key = key
          decipher.iv = nonce
          decipher.auth_tag = tag
          (decipher.update(data) + decipher.final).force_encoding('UTF-8')
        rescue OpenSSL::Cipher::CipherError
          raise ArgumentError, 'decryption failed: wrong key or tampered value'
        end

        private

        # Split and decode a self-contained ciphertext into its parts.
        #
        # @param ciphertext [String]
        # @return [Array<String>] the nonce, tag and data, decoded
        # @raise [ArgumentError] if the ciphertext is not three dot-separated
        #   base64 segments
        sig { params(ciphertext: String).returns(T::Array[String]) }
        def split_ciphertext(ciphertext)
          # The negative limit keeps a trailing empty segment, which is what an
          # empty plaintext produces; split would otherwise drop it.
          nonce_b64, tag_b64, data_b64 = ciphertext.split('.', -1)
          raise ArgumentError, 'malformed ciphertext' unless nonce_b64 && tag_b64 && data_b64

          [
            Base64.strict_decode64(nonce_b64),
            Base64.strict_decode64(tag_b64),
            Base64.strict_decode64(data_b64)
          ]
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
