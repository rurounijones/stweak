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

      # @param password [Stweak::Domain::Accounts::PasswordPlainText] the raw password
      # @return [Stweak::Domain::Accounts::PasswordHash] the bcrypt hash
      sig do
        override.params(password: Stweak::Domain::Accounts::PasswordPlainText)
                .returns(Stweak::Domain::Accounts::PasswordHash)
      end
      def digest(password:)
        # to_s, not the BCrypt::Password object: the object's == compares a
        # plaintext candidate against the hash, which the port does not want.
        Stweak::Domain::Accounts::PasswordHash.new(value: BCrypt::Password.create(password.plaintext).to_s)
      end

      # Verify a password against a bcrypt hash, returning false for an
      # invalid or incompatible stored value.
      #
      # @param password [Stweak::Domain::Accounts::PasswordPlainText] the raw password
      # @param digest [Stweak::Domain::Accounts::PasswordHash] the bcrypt hash
      # @return [Boolean]
      sig do
        override.params(password: Stweak::Domain::Accounts::PasswordPlainText,
                        digest: Stweak::Domain::Accounts::PasswordHash).returns(T::Boolean)
      end
      def verify(password:, digest:)
        BCrypt::Password.new(digest.to_stored) == password.plaintext
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end
  end
end
