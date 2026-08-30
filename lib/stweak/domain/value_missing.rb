# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Domain
    # The value of a field whose owner's encryption key was shredded under a
    # GDPR erasure. The data is gone permanently and by design: reading the
    # field yields ValueMissing rather than raising, because a missing key is
    # a normal state, not an error. A module used as a value, so a field that
    # is encrypted can be either its plain value or ValueMissing — a union
    # that is less ambiguous than a bare nil.
    module ValueMissing
      extend T::Sig

      # The wire form of a shredded field is the marker itself, so a serializer
      # can call to_stored on either a value object or this marker and get back
      # plain, serializable data either way. This is the marker's half of the
      # pairing that lets serialization avoid a type check; the value objects
      # return their string. See the value objects' own to_stored.
      #
      # @return [Class<Stweak::Domain::ValueMissing>]
      sig { returns(T.class_of(ValueMissing)) }
      def self.to_stored
        self
      end
    end
  end
end
