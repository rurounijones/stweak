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
      # cannot be handed a username or an email by mistake.
      #
      # Validated for shape at construction, so an unusable name can never
      # circulate: it must be no more than {MAX_LENGTH} characters, hold at
      # least one non-whitespace character, and contain no control characters.
      # The rules are deliberately looser than a username's because a display
      # name is human-facing text: it may hold spaces, punctuation and non-ASCII
      # letters, so only the length cap, the all-blank name and control
      # characters (which have no place in shown text and are a classic
      # injection vector) are refused. The rejection message never quotes the
      # value: a display name is personal data, and naming it in an error would
      # be exactly the leak {#to_s} guards against.
      #
      # Equality is by value: two display names are equal when they are exactly
      # the same class carrying the same string. It carries no shared base with
      # the other value objects by design — each stands on its own.
      #
      # The display name is personal data, so the string-rendering operations
      # mask it: {#to_s} and {#inspect} return {MASK} rather than the name, so a
      # display name that leaks into a log line, an error message or an
      # interpolated string reveals nothing. The real name is reachable only
      # through {#pii}, whose name forces a caller to acknowledge it is handling
      # personal data, and through {#to_stored}, the serialization boundary that
      # feeds the encrypting store. There is no plain +value+ reader: taking the
      # name is always a deliberate, named act.
      class DisplayName
        extend T::Sig

        # What the string-rendering operations return in place of the name.
        MASK = '*****'

        # The longest a display name may be, in characters.
        MAX_LENGTH = 50

        # Matches a string that contains a control character, which a display
        # name may not.
        CONTROL = /[[:cntrl:]]/

        # Matches a string that holds at least one non-whitespace character,
        # which a display name must. Preferred over stripping and testing for
        # empty: an all-whitespace string is empty whether stripped on one side
        # or both, so the strip form leaves left/right-strip mutants that no
        # test can kill, while this asks the question directly.
        NON_BLANK = /\S/

        # @param value [String] the display name: at most {MAX_LENGTH}
        #   characters, not all whitespace, and free of control characters
        # @raise [Stweak::Domain::ValidationError] if value breaks any of those
        #   rules
        sig { params(value: String).void }
        def initialize(value:)
          # `valid_encoding?` short-circuits the rest: on a non-UTF-8 string,
          # `match?` itself raises ArgumentError rather than returning false.
          # The value is not quoted in the message — a display name is personal
          # data.
          valid = value.valid_encoding? && value.match?(NON_BLANK) &&
                  value.length <= MAX_LENGTH && !value.match?(CONTROL)
          unless valid
            raise ValidationError,
                  "name must be at most #{MAX_LENGTH} characters, not blank, " \
                  'and free of control characters'
          end

          @value = value
        end

        # Rebuild from a value already taken from the store, which is trusted
        # and so is wrapped without re-validating. The value came from the event
        # log, and at the encrypting store's boundary it is ciphertext rather
        # than a well-formed name, so re-checking its shape would be both wrong
        # and impossible. This is the read-back counterpart to {#initialize},
        # which validates a name arriving from outside the domain; the split is
        # why encryption can round-trip an event through {AccountCreated.from_h}
        # without the format rule rejecting the ciphertext.
        #
        # @param value [String] the stored value, trusted as-is
        # @return [DisplayName]
        sig { params(value: String).returns(DisplayName) }
        def self.from_stored(value)
          name = allocate
          name.instance_variable_set(:@value, value)
          name
        end

        # The real display name. Named for what it is: reading it is handling
        # personal data, and a caller has to say so to get it.
        #
        # @return [String]
        sig { returns(String) }
        def pii
          @value
        end

        # The display name, masked. Personal data does not render itself in the
        # clear, so this returns {MASK} rather than the name; use {#pii} for the
        # real value.
        #
        # @return [String]
        sig { returns(String) }
        def to_s
          MASK
        end

        # The display name, masked, for a log line or console. As {#to_s}:
        # personal data does not render itself in the clear.
        #
        # @return [String]
        sig { returns(String) }
        def inspect
          MASK
        end

        # The value as stored on the wire: the plain name. This is the
        # serialization boundary that feeds the encrypting store, so it returns
        # the real value rather than the mask. Paired with
        # {Stweak::Domain::ValueMissing.to_stored}, so a serializer can call
        # to_stored on either a display name or the shredded-field marker and get
        # back plain data, without testing which of the two it holds.
        #
        # @return [String]
        sig { returns(String) }
        def to_stored
          pii
        end

        # Two display names are equal when they are exactly the same class
        # carrying the same value.
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

        # Consistent with #eql?, so display names work as hash keys.
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
