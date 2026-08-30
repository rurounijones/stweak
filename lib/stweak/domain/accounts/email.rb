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
      # display name or a username by mistake. Validated non-empty at
      # construction; the shape of a valid address is a later concern.
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

        # @param value [String] the email, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'email must not be empty' if value.empty?

          @value = value
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
