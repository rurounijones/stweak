# typed: strict
# frozen_string_literal: true

require 'bcrypt'
require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # A password hasher backed by bcrypt: the real, well-known implementation
    # of Stweak::Domain::Security::PasswordHasher, living alongside the domain
    # gem's stdlib PBKDF2 one to prove the port is interchangeable. The stored
    # format differs from the gem's (bcrypt's `$2` prefix rather than
    # PBKDF2's), which is the point: the domain only ever sees an opaque
    # digest.
    class BcryptPasswordHasher
      include Stweak::Domain::Security::PasswordHasher

      extend T::Sig

      # @param password [String] the raw password
      # @return [String] the bcrypt hash
      sig { override.params(password: String).returns(String) }
      def digest(password:)
        # to_s, not the BCrypt::Password object: the object's == compares a
        # plaintext candidate against the hash, which the port does not want.
        BCrypt::Password.create(password).to_s
      end

      # Verify a password against a bcrypt digest, returning false for an
      # invalid or incompatible stored value.
      #
      # @param password [String] the raw password
      # @param digest [String] the bcrypt hash
      # @return [Boolean]
      sig { override.params(password: String, digest: String).returns(T::Boolean) }
      def verify(password:, digest:)
        BCrypt::Password.new(digest) == password
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end
  end
end
