# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'

module Stweak
  module Domain
    module Accounts
      # A hashed password: the digest a {Stweak::Domain::Security::PasswordHasher}
      # produces from a {PasswordPlainText}, stored on the account and checked at
      # authentication. A named type rather than a bare String, so a signature
      # that asks for a hash cannot be handed a raw password, and the digest that
      # goes into the event log is the digest that comes back out.
      #
      # Validated for coherence only, and deliberately opaque: a hash must not be
      # empty, and nothing else is checked. The domain does not know which
      # algorithm produced the value — PBKDF2 and bcrypt write different formats,
      # and choosing between them is the adapter's decision, not the domain's — so
      # there is no shape to validate beyond the absence of a hash. Whether a
      # string is a well-formed digest is the hasher's business; whether one is
      # present is the type's.
      #
      # Unlike a display name or an email, a hash is not personal data: it is
      # already unreadable, so it is stored unencrypted and never crypto-shredded,
      # and it renders plainly like a {Username} rather than masking itself. That
      # is also why it is rebuilt on read through the ordinary constructor, which
      # re-validates: the stored value is always the real, once-valid digest,
      # never ciphertext, so there is no trusting +from_stored+ seam of the kind
      # the encrypted types carry.
      #
      # Equality is by value, so two hashes are equal when they carry the same
      # digest. It carries no shared base with the other value objects by design —
      # each stands on its own.
      class PasswordHash
        extend T::Sig

        # @param value [String] the digest, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'password hash must not be empty' if value.empty?

          @value = value
        end

        # The digest as a plain string. A hash is not personal data and is already
        # unreadable, so it renders in the clear rather than masking itself.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          @value
        end

        # The value as stored on the wire: the plain digest. Paired with
        # {Stweak::Domain::ValueMissing.to_stored} so a serializer can call
        # to_stored without testing which it holds — though a hash is never
        # shredded, the pairing keeps the serialization boundary uniform.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          @value
        end

        # Two hashes are equal when they are exactly the same class carrying the
        # same digest.
        #
        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.instance_of?(self.class)

          to_s == other.to_s
        end

        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def eql?(other)
          self == other
        end

        # Consistent with #eql?, so hashes work as hash keys.
        #
        # @return [Integer]
        sig { returns(Integer) }
        def hash
          to_s.hash
        end
      end
    end
  end
end
