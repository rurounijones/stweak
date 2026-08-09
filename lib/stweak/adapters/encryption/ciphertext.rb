# typed: strict
# frozen_string_literal: true

require 'base64'
require 'sorbet-runtime'

module Stweak
  module Adapters
    module Encryption
      # A self-contained encrypted value: a base64 nonce, authentication tag and
      # ciphertext, dot separated. A named type rather than a bare String, so a
      # signature that asks for a ciphertext cannot be handed a plaintext or a
      # key, and a value read back from a store is parsed into its parts before
      # a cipher ever sees it.
      #
      # Validated for shape at construction, so a malformed value can never
      # circulate: it must be exactly {SEGMENTS} dot-separated strict-base64
      # segments. The format belongs here rather than in the cipher because it
      # is the ciphertext's own envelope — the value's stored form and its
      # decoded parts are the same fact, and keeping them together means the
      # cipher only ever receives a value it can split.
      #
      # A ciphertext is not personal data: it is already unreadable, so it
      # renders plainly like a password hash rather than masking itself.
      #
      # Equality is by value, so two ciphertexts are equal when they carry the
      # same envelope. It carries no shared base with the other value objects by
      # design — each stands on its own.
      class Ciphertext
        extend T::Sig

        # The number of dot-separated segments in a self-contained ciphertext.
        SEGMENTS = 3

        # The nonce, decoded from its base64 segment.
        #
        # @return [String] the raw nonce bytes
        sig { returns(String) }
        attr_reader :nonce

        # The authentication tag, decoded from its base64 segment.
        #
        # @return [String] the raw tag bytes
        sig { returns(String) }
        attr_reader :tag

        # The ciphertext, decoded from its base64 segment.
        #
        # @return [String] the raw ciphertext bytes
        sig { returns(String) }
        attr_reader :data

        # @param value [String] the stored envelope: {SEGMENTS} dot-separated
        #   base64 segments
        # @raise [ArgumentError] if value is not a well-formed ciphertext
        sig { params(value: String).void }
        def initialize(value:)
          nonce, tag, data = decode(value)
          @nonce = T.let(nonce, String)
          @tag = T.let(tag, String)
          @data = T.let(data, String)
        end

        # The ciphertext as stored on the wire: its parts re-encoded and dot
        # separated. A ciphertext is not personal data and is already
        # unreadable, so it renders in the clear rather than masking itself.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          [nonce, tag, data].map { |part| Base64.strict_encode64(part) }.join('.')
        end

        # The stored envelope as a plain string. As {#to_stored}: a ciphertext is
        # already unreadable.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          to_stored
        end

        # Two ciphertexts are equal when they are exactly the same class
        # carrying the same envelope.
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

        # Consistent with #eql?, so ciphertexts work as hash keys.
        #
        # @return [Integer]
        sig { returns(Integer) }
        def hash
          to_stored.hash
        end

        private

        # Split and decode a stored envelope into its nonce, tag and data.
        #
        # @param value [String]
        # @return [[String, String, String]] the nonce, tag and data, decoded
        # @raise [ArgumentError] if value is not {SEGMENTS} dot-separated base64
        #   segments, or a segment is not strict base64
        sig { params(value: String).returns([String, String, String]) }
        def decode(value)
          parts = segments(value)
          raise ArgumentError, 'malformed ciphertext' unless parts.length == SEGMENTS

          [
            Base64.strict_decode64(parts.fetch(0)),
            Base64.strict_decode64(parts.fetch(1)),
            Base64.strict_decode64(parts.fetch(2))
          ]
        end

        # The dot-separated segments of a stored ciphertext. Isolated into its
        # own method because the negative split limit — which keeps the trailing
        # empty segment an empty plaintext produces, where split would otherwise
        # drop it — has only equivalent mutants: any negative limit is
        # unlimited, so no test can tell -1 from -2. It is ignored in
        # .mutant.yml for that reason, leaving #decode's length guard fully
        # mutated.
        #
        # @param value [String]
        # @return [Array<String>]
        sig { params(value: String).returns(T::Array[String]) }
        def segments(value)
          value.split('.', -1)
        end
      end
    end
  end
end
