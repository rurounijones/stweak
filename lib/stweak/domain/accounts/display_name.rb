# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'

module Stweak
  module Domain
    module Accounts
      # An account's display name: the name shown for the account, personal
      # data encrypted at rest, and the target of a forced rename. A named type
      # rather than a bare String, so a signature that asks for a display name
      # cannot be handed a username or an email by mistake. Validated non-empty
      # at construction; deeper rules on an acceptable name are a later concern.
      #
      # Equality is by value: two display names are equal when they are exactly
      # the same class carrying the same string. It carries no shared base with
      # the other value objects by design — each stands on its own.
      class DisplayName
        extend T::Sig

        sig { returns(String) }
        attr_reader :value

        # @param value [String] the display name, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'name must not be empty' if value.empty?

          @value = value
        end

        # The display name as a plain string.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          value
        end

        # The value as stored on the wire: the plain string. Paired with
        # {Stweak::Domain::ValueMissing.to_stored}, so a serializer can call
        # to_stored on either a display name or the shredded-field marker and get
        # back plain data, without testing which of the two it holds.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          value
        end

        # Two display names are equal when they are exactly the same class
        # carrying the same value.
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

        # Consistent with #eql?, so display names work as hash keys.
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
