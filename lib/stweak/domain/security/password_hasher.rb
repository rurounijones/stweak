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

        # Digest a password into a self-describing string that a future verify
        # can be added to without changing what is stored.
        #
        # @param password [String]
        # @return [String]
        sig { abstract.params(password: String).returns(String) }
        def digest(password:); end
      end
    end
  end
end
