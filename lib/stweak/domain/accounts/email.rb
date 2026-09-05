# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'

module Stweak
  module Domain
    module Accounts
      # An account's email address: personal data, encrypted at rest, and the
      # textbook value that means more than its class. A named type rather than
      # a bare String, so a signature that asks for an email cannot be handed a
      # display name or a username by mistake.
      #
      # Validated for shape at construction, so a malformed address can never
      # circulate: it must be a non-empty local part and a non-empty domain
      # separated by a single +@+, with no whitespace anywhere ({PATTERN}).
      # This is deliberately loose — the full grammar of a valid address is
      # famously baroque and only the mail server truly knows if one deliverable
      # — so the rule catches the obvious mistake (+"x"+, a missing +@+, a stray
      # space) without pretending to be RFC 5322. The rejection message never
      # quotes the value: an email is personal data, and naming it in an error
      # would be exactly the leak {#to_s} guards against.
      #
      # Equality is by value: two emails are equal when they are exactly the
      # same class carrying the same string. It carries no shared base with the
      # other value objects by design — each stands on its own.
      #
      # The email is personal data, so the string-rendering operations mask it:
      # {#to_s} and {#inspect} return {MASK} rather than the address, so an
      # email that leaks into a log line, an error message or an interpolated
      # string reveals nothing. The real address is reachable only through
      # {#pii}, whose name forces a caller to acknowledge it is handling
      # personal data, and through {#to_stored}, the serialization boundary that
      # feeds the encrypting store. There is no plain +value+ reader: taking the
      # address is always a deliberate, named act.
      class Email
        extend T::Sig

        # What the string-rendering operations return in place of the address.
        MASK = '*****'

        # A valid email: a non-empty local part and a non-empty domain, each
        # free of whitespace and +@+, separated by a single +@+.
        PATTERN = /\A[^@\s]+@[^@\s]+\z/

        # @param value [String] the email, which must match {PATTERN}
        # @raise [Stweak::Domain::ValidationError] if value does not match
        #   {PATTERN}
        sig { params(value: String).void }
        def initialize(value:)
          # `valid_encoding?` short-circuits the regex: on a non-UTF-8 string,
          # `match?` itself raises ArgumentError rather than returning false.
          # The value is not quoted in the message — an email is personal data.
          valid = value.valid_encoding? && value.match?(PATTERN)
          raise ValidationError, 'email must be a local part and a domain separated by @' unless valid

          @value = value
        end

        # Rebuild from a value already taken from the store, which is trusted
        # and so is wrapped without re-validating. The value came from the event
        # log, and at the encrypting store's boundary it is ciphertext rather
        # than a well-formed address, so re-checking its shape would be both
        # wrong and impossible. This is the read-back counterpart to {#initialize},
        # which validates an address arriving from outside the domain; the split
        # is why encryption can round-trip an event through {AccountCreated.from_h}
        # without the format rule rejecting the ciphertext.
        #
        # @param value [String] the stored value, trusted as-is
        # @return [Email]
        sig { params(value: String).returns(Email) }
        def self.from_stored(value)
          email = allocate
          email.instance_variable_set(:@value, value)
          email
        end

        # The real email address. Named for what it is: reading it is handling
        # personal data, and a caller has to say so to get it.
        #
        # @return [String]
        sig { returns(String) }
        def pii
          @value
        end

        # The email, masked. Personal data does not render itself in the clear,
        # so this returns {MASK} rather than the address; use {#pii} for the
        # real value.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          MASK
        end

        # The email, masked, for a log line or console. As {#to_s}: personal
        # data does not render itself in the clear.
        #
        # @return [String]
        sig { returns(String) }
        def inspect
          MASK
        end

        # The value as stored on the wire: the plain address. This is the
        # serialization boundary that feeds the encrypting store, so it returns
        # the real value rather than the mask. Paired with
        # {Stweak::Domain::ValueMissing.to_stored}, so a serializer can call
        # to_stored on either an email or the shredded-field marker and get back
        # plain data, without testing which of the two it holds.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          pii
        end

        # Two emails are equal when they are exactly the same class carrying the
        # same value.
        #
        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.instance_of?(self.class)

          pii == other.pii
        end

        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def eql?(other)
          self == other
        end

        # Consistent with #eql?, so emails work as hash keys.
        #
        # @return [Integer]
        sig { returns(Integer) }
        def hash
          pii.hash
        end
      end
    end
  end
end
