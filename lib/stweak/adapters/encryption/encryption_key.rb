# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Adapters
    module Encryption
      # AES-256 key material: the 32 raw bytes a cipher encrypts and decrypts
      # under. A named type rather than a bare String, so a signature that asks
      # for a key cannot be handed a plaintext, a ciphertext or a stored value,
      # and the key that goes into the key store is the key that comes back out.
      #
      # Validated for length at construction. Unlike a password, whose strength
      # is acceptance policy, a key's length is the algorithm's requirement:
      # AES-256 takes exactly 32 bytes, and anything else is not a key at all.
      # Making that unrepresentable moves the cipher's length guard onto the
      # type, so the cipher only ever receives a key it can use.
      #
      # A key is a secret, so the string-rendering operations mask it: {#to_s}
      # and {#inspect} return {MASK} rather than the bytes, so a key that leaks
      # into a log line, an error message or an interpolated string reveals
      # nothing. The real bytes are reachable only through {#to_stored}, whose
      # name marks it as the serialization boundary the key store writes and the
      # cipher reads.
      #
      # Equality is by value, so two keys are equal when they carry the same
      # bytes. It carries no shared base with the other value objects by design
      # — each stands on its own.
      class EncryptionKey
        extend T::Sig

        # What the string-rendering operations return in place of the key.
        MASK = '*****'

        # The length of an AES-256 key, in bytes.
        LENGTH = 32

        # @param value [String] the raw key, which must be {LENGTH} bytes
        # @raise [ArgumentError] if value is not {LENGTH} bytes
        sig { params(value: String).void }
        def initialize(value:)
          raise ArgumentError, "key must be #{LENGTH} bytes" unless value.bytesize == LENGTH

          @value = value
        end

        # The key as stored on the wire: the raw bytes. This is the
        # serialization boundary the key store writes and the cipher reads, so
        # it returns the real key rather than the mask.
        #
        # @return [String] {LENGTH} raw bytes
        sig { returns(String) }
        def to_stored
          @value
        end

        # The key, masked. A secret does not render itself in the clear, so this
        # returns {MASK} rather than the bytes; use {#to_stored} for the real
        # key.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          MASK
        end

        # The key, masked, for a log line or console. As {#to_s}: a secret does
        # not render itself in the clear.
        #
        # @return [String]
        sig { returns(String) }
        def inspect
          MASK
        end

        # Two keys are equal when they are exactly the same class carrying the
        # same bytes.
        #
        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.instance_of?(self.class)

          to_stored == other.to_stored
        end

        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def eql?(other)
          self == other
        end

        # Consistent with #eql?, so keys work as hash keys.
        #
        # @return [Integer]
        sig { returns(Integer) }
        def hash
          to_stored.hash
        end
      end
    end
  end
end
