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
      # value.
      #
      # Validated for shape at construction, so an invalid username can never
      # circulate: it must be 3 to 30 characters of ASCII letters, digits,
      # underscore or hyphen ({PATTERN}). That charset is deliberately narrow —
      # a username is a login handle and a uniqueness key, not display text, so
      # whitespace, control characters and punctuation have no place in it, and
      # excluding them keeps the value safe to embed in a log line or an error
      # message. The username is not personal data (it must survive
      # crypto-shredding for the uniqueness check to keep working), so it renders
      # plainly and the bad value is named in the rejection message.
      #
      # Equality is by value: two usernames are equal when they are exactly the
      # same class carrying the same string. It carries no shared base with the
      # other value objects by design — each stands on its own.
      class Username
        extend T::Sig

        # A valid username: 3 to 30 characters of ASCII letters, digits,
        # underscore or hyphen, and nothing else.
        PATTERN = /\A[A-Za-z0-9_-]{3,30}\z/

        sig { returns(String) }
        attr_reader :value

        # @param value [String] the username, which must match {PATTERN}
        # @raise [Stweak::Domain::ValidationError] if value does not match
        #   {PATTERN}
        sig { params(value: String).void }
        def initialize(value:)
          # `valid_encoding?` short-circuits the regex: on a non-UTF-8 string,
          # `match?` itself raises ArgumentError rather than returning false.
          valid = value.valid_encoding? && value.match?(PATTERN)
          unless valid
            raise ValidationError,
                  'username must be 3 to 30 characters of letters, digits, ' \
                  "underscore or hyphen, got: #{value.inspect}"
          end

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
