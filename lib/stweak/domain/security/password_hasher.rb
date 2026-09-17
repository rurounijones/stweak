# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../accounts/password_hash'
require_relative '../accounts/password_plain_text'

module Stweak
  module Domain
    # Security concerns the domain relies on, expressed as ports.
    module Security
      # The port the domain digests passwords through. Password hashing is a
      # domain concern — the handler needs a digest, never the raw password —
      # but the algorithm is a technology the domain does not know about. The
      # port speaks the domain's value objects at both ends: it takes a
      # {Stweak::Domain::Accounts::PasswordPlainText} and returns a
      # {Stweak::Domain::Accounts::PasswordHash}, so a caller cannot hand it the
      # wrong string or mistake its result for a raw password. Taking the secret
      # out is the adapter's business, through PasswordPlainText#plaintext.
      #
      # The method is called `digest` rather than `hash` deliberately: `hash`
      # collides with `Kernel#hash`, which would make an implementor unusable
      # as a hash key and trips Sorbet's override check.
      module PasswordHasher
        extend T::Sig
        extend T::Helpers

        interface!

        # Digest a password into a self-describing hash.
        #
        # @param password [Stweak::Domain::Accounts::PasswordPlainText]
        # @return [Stweak::Domain::Accounts::PasswordHash]
        sig { abstract.params(password: Accounts::PasswordPlainText).returns(Accounts::PasswordHash) }
        def digest(password:); end

        # Whether a raw password matches a stored hash. Invalid or unknown
        # hash formats return false rather than raising a caller-facing error.
        #
        # @param password [Stweak::Domain::Accounts::PasswordPlainText]
        # @param digest [Stweak::Domain::Accounts::PasswordHash]
        # @return [Boolean]
        sig do
          abstract.params(password: Accounts::PasswordPlainText, digest: Accounts::PasswordHash)
                  .returns(T::Boolean)
        end
        def verify(password:, digest:); end
      end
    end
  end
end
