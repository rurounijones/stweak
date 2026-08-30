# typed: strict
# frozen_string_literal: true

require 'json'
require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # Shared serialization for events crossing an adapter boundary: an event is
    # stored as its serialized form, which carries its type name, and rebuilt by
    # looking the type up in the registry.
    module EventSerialization
      extend T::Sig

      # The event classes the adapters can rebuild, keyed by the type name each
      # declares and serializes under. Keying on the event's own TYPE constant
      # keeps the registry and the event in lockstep — the key cannot drift from
      # what the event writes — and it grows as the domain adds events.
      EVENT_CLASSES = T.let(
        {
          Stweak::Domain::Accounts::AccountCreated::TYPE => Stweak::Domain::Accounts::AccountCreated,
          Stweak::Domain::Accounts::AccountDisabled::TYPE => Stweak::Domain::Accounts::AccountDisabled,
          Stweak::Domain::Accounts::AccountDeleted::TYPE => Stweak::Domain::Accounts::AccountDeleted
        }.freeze,
        T::Hash[String, T.class_of(Stweak::Domain::Event)]
      )

      # @param event [Stweak::Domain::Event]
      # @return [String]
      sig { params(event: Stweak::Domain::Event).returns(String) }
      def serialize(event)
        JSON.generate(event.to_h)
      end

      # @param data [String]
      # @return [Stweak::Domain::Event]
      sig { params(data: String).returns(Stweak::Domain::Event) }
      def deserialize(data)
        hash = JSON.parse(data)
        klass = EVENT_CLASSES.fetch(hash.fetch('type'))
        klass.from_h(klass.upcast(hash))
      end
    end
  end
end
