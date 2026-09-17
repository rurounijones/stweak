# typed: strict
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'sorbet-runtime'
require_relative '../../domain/accounts/password_hash'
require_relative '../../domain/accounts/password_plain_text'
require_relative '../../domain/security/password_hasher'

module Stweak
  module Adapters
    # Security adapters.
    module Security
      # PBKDF2-HMAC-SHA256 password hashing with a per-password random salt,
      # using only the stdlib. The hash is self-describing so that a future
      # `verify` can be added without changing what is stored.
      class Pbkdf2PasswordHasher
        include Stweak::Domain::Security::PasswordHasher

        extend T::Sig

        # The default iteration count. Tests pass a smaller value to stay fast.
        DEFAULT_ITERATIONS = 200_000

        # @param iterations [Integer] the PBKDF2 work factor
        sig { params(iterations: Integer).void }
        def initialize(iterations: DEFAULT_ITERATIONS)
          @iterations = iterations
        end

        # Digest a password into the format
        # `pbkdf2-sha256$<iterations>$<salt>$<hash>`, all base64. The secret is
        # taken out of the value object here, at the boundary that consumes it.
        #
        # @param password [Stweak::Domain::Accounts::PasswordPlainText]
        # @return [Stweak::Domain::Accounts::PasswordHash]
        sig do
          override.params(password: Stweak::Domain::Accounts::PasswordPlainText)
                  .returns(Stweak::Domain::Accounts::PasswordHash)
        end
        def digest(password:)
          salt = random_salt
          derived = OpenSSL::PKCS5.pbkdf2_hmac(password.plaintext, salt, @iterations, 32, 'SHA256')

          Domain::Accounts::PasswordHash.new(
            value: "pbkdf2-sha256$#{@iterations}$#{Base64.strict_encode64(salt)}$#{Base64.strict_encode64(derived)}"
          )
        end

        # Verify a password against a PBKDF2 hash, returning false for an
        # invalid or incompatible stored value.
        #
        # @param password [Stweak::Domain::Accounts::PasswordPlainText]
        # @param digest [Stweak::Domain::Accounts::PasswordHash]
        # @return [Boolean]
        sig do
          override.params(password: Stweak::Domain::Accounts::PasswordPlainText,
                          digest: Stweak::Domain::Accounts::PasswordHash).returns(T::Boolean)
        end
        def verify(password:, digest:)
          parsed = parse(digest.to_stored)
          return false unless parsed

          salt, expected, iteration_count = parsed
          actual = OpenSSL::PKCS5.pbkdf2_hmac(password.plaintext, salt, iteration_count, expected.bytesize, 'SHA256')
          OpenSSL.fixed_length_secure_compare(actual, expected)
        end

        private

        # A fresh 16-byte salt from the system CSPRNG. Isolated into its own
        # method so `digest` stays fully mutated: this call has no behaviour a
        # test can pin — any 16 secure-random bytes serve identically — so its
        # only surviving mutants swap one such source for another, and it is
        # ignored in `.mutant.yml` for that reason.
        #
        # @return [String] 16 raw bytes
        sig { returns(String) }
        def random_salt
          OpenSSL::Random.random_bytes(16)
        end

        # Parse a stored digest into its salt, expected hash and iteration
        # count, or nil for anything malformed or incompatible.
        #
        # @param digest [String]
        # @return [Array(String, String, Integer), nil]
        sig { params(digest: String).returns(T.nilable([String, String, Integer])) }
        def parse(digest)
          parts = digest.split('$')
          return unless parts.length == 4 && parts.fetch(0) == 'pbkdf2-sha256'

          iteration_count = Integer(parts.fetch(1))
          return unless iteration_count.positive?

          expected = Base64.strict_decode64(parts.fetch(3))
          return unless expected.bytesize == 32

          [Base64.strict_decode64(parts.fetch(2)), expected, iteration_count]
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
