# typed: strict
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'sorbet-runtime'
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
        # `pbkdf2-sha256$<iterations>$<salt>$<hash>`, all base64.
        #
        # @param password [String]
        # @return [String]
        sig { override.params(password: String).returns(String) }
        def digest(password:)
          salt = OpenSSL::Random.random_bytes(16)
          derived = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, @iterations, 32, 'SHA256')

          "pbkdf2-sha256$#{@iterations}$#{Base64.strict_encode64(salt)}$#{Base64.strict_encode64(derived)}"
        end
      end
    end
  end
end
