# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Domain
    # Security concerns the domain relies on, expressed as ports.
    module Security
      # The port the domain digests passwords through. Password hashing is a
      # domain concern — the handler needs a digest, never the raw password —
      # but the algorithm is a technology the domain does not know about.
      #
      # The method is called `digest` rather than `hash` deliberately: `hash`
      # collides with `Kernel#hash`, which would make an implementor unusable
      # as a hash key and trips Sorbet's override check.
      module PasswordHasher
        extend T::Sig
        extend T::Helpers

        interface!

        # Digest a password into a self-describing string.
        #
        # @param password [String]
        # @return [String]
        sig { abstract.params(password: String).returns(String) }
        def digest(password:); end

        # Whether a raw password matches a stored digest. Invalid or unknown
        # digest formats return false rather than raising a caller-facing error.
        #
        # @param password [String]
        # @param digest [String]
        # @return [Boolean]
        sig { abstract.params(password: String, digest: String).returns(T::Boolean) }
        def verify(password:, digest:); end
      end
    end
  end
end
