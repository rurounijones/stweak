# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../error'

module Stweak
  module Domain
    module Accounts
      # An account's username: the handle it logs in and is found by, and the
      # value the cross-account uniqueness rule is enforced on. A named type
      # rather than a bare String, so a signature that asks for a username
      # cannot be handed an arbitrary string, and the meaning travels with the
      # value. Validated non-empty at construction, so an invalid username can
      # never circulate; format and charset rules are a later concern.
      #
      # Equality is by value: two usernames are equal when they are exactly the
      # same class carrying the same string. It carries no shared base with the
      # other value objects by design — each stands on its own.
      class Username
        extend T::Sig

        sig { returns(String) }
        attr_reader :value

        # @param value [String] the username, which must not be empty
        # @raise [Stweak::Domain::ValidationError] if value is empty
        sig { params(value: String).void }
        def initialize(value:)
          raise ValidationError, 'username must not be empty' if value.empty?

          @value = value
        end

        # The username as a plain string.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          value
        end

        # Two usernames are equal when they are exactly the same class carrying
        # the same value.
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

        # Consistent with #eql?, so usernames work as hash keys.
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
