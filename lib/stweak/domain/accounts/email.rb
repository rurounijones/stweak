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
      class Email
        extend T::Sig

        sig { returns(String) }
        attr_reader :value

        # @param value [String] the email, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'email must not be empty' if value.empty?

          @value = value
        end

        # The email as a plain string.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          value
        end

        # The value as stored on the wire: the plain string. Paired with
        # {Stweak::Domain::ValueMissing.to_stored}, so a serializer can call
        # to_stored on either an email or the shredded-field marker and get back
        # plain data, without testing which of the two it holds.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          value
        end

        # Two emails are equal when they are exactly the same class carrying the
        # same value.
        #
        # @param other [Object]
        # @return [Boolean]
        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.instance_of?(self.class)

          value == other.value
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
          value.hash
        end
      end
    end
  end
end
