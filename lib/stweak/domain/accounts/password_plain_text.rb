# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'

module Stweak
  module Domain
    module Accounts
      # A raw, unhashed password as it arrives from a caller: the secret carried
      # by {CreateAccount} and checked by {AuthenticateAccount}, on its way to the
      # {Stweak::Domain::Security::PasswordHasher} port. A named type rather than a
      # bare String, so a signature that asks for a plaintext password cannot be
      # handed a username or a hash, and the hasher is the only thing that ever
      # takes the secret out.
      #
      # Validated for coherence only: a password must not be empty, because an
      # empty string is the absence of a secret rather than a secret. Nothing more
      # is checked here. Strength — a minimum length, a mix of character classes,
      # a rejection of known-breached values — is acceptance policy, not a shape
      # invariant: it is mutable, it belongs to the application deciding what it
      # will accept, and every non-empty string is a structurally coherent
      # password. Length caps against a hashing denial of service are the hasher
      # adapter's concern, at the boundary where the cost is actually paid. So the
      # only thing that cannot be represented is the empty one.
      #
      # A password is a secret, so the string-rendering operations mask it: {#to_s}
      # and {#inspect} return {MASK} rather than the value, so a password that
      # leaks into a log line, an error message or an interpolated string reveals
      # nothing. The real value is reachable only through {#plaintext}, whose name
      # forces a caller to acknowledge it is taking the secret out. It is a
      # credential rather than personal data, so the accessor is named for what it
      # is rather than borrowing the +pii+ name the personal-data types use, and
      # there is deliberately no +to_stored+: the raw password is never
      # serialized, never reaches any store, and never appears in the event log.
      #
      # Equality is by value, so two plaintext passwords are equal when they carry
      # the same secret. It carries no shared base with the other value objects by
      # design — each stands on its own.
      class PasswordPlainText
        extend T::Sig

        # What the string-rendering operations return in place of the password.
        MASK = '*****'

        # @param value [String] the raw password, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'password must not be empty' if value.empty?

          @value = value
        end

        # The real password. Named for what it is: reading it takes the secret
        # out, and a caller has to say so to get it. This is the only way through
        # to the value, and the hasher port is its only intended caller.
        #
        # @return [String]
        sig { returns(String) }
        def plaintext
          @value
        end

        # The password, masked. A secret does not render itself in the clear, so
        # this returns {MASK} rather than the value; use {#plaintext} to take the
        # secret out.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          MASK
        end

        # The password, masked, for a log line or console. As {#to_s}: a secret
        # does not render itself in the clear.
        #
        # @return [String]
        sig { returns(String) }
        def inspect
          MASK
        end

        # Two plaintext passwords are equal when they are exactly the same class
        # carrying the same secret.
        #
        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.instance_of?(self.class)

          plaintext == other.plaintext
        end

        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def eql?(other)
          self == other
        end

        # Consistent with #eql?, so plaintext passwords work as hash keys.
        #
        # @return [Integer]
        sig { returns(Integer) }
        def hash
          plaintext.hash
        end
      end
    end
  end
end
