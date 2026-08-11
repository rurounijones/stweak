# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'aggregate'
require_relative 'event'
require_relative 'accounts/account'
require_relative 'accounts/account_created'

module Stweak
  module Domain
    # Maps event classes to the aggregate class whose stream they belong to.
    # Centralising the mapping is what lets an event know nothing about its
    # aggregate: Event and each event carry no reference to the class that owns
    # them, so the require graph stays acyclic — see "Explicit requires" in the
    # design decisions. This file is the single source of truth for "which
    # events exist and who owns them"; a new aggregate registers its events here.
    module OwnerRegistry
      extend T::Sig

      @owners = T.let({}, T::Hash[T.class_of(Event), T.class_of(Aggregate)])

      # Record which aggregate class owns an event's stream.
      #
      # @param event_class [Class<Stweak::Domain::Event>]
      # @param aggregate_class [Class<Stweak::Domain::Aggregate>]
      sig do
        params(
          event_class: T.class_of(Event),
          aggregate_class: T.class_of(Aggregate)
        ).void
      end
      def self.register(event_class:, aggregate_class:)
        @owners[event_class] = aggregate_class
      end

      # The aggregate class that owns an event's stream.
      #
      # @param event_class [Class<Stweak::Domain::Event>]
      # @return [Class<Stweak::Domain::Aggregate>]
      # @raise [KeyError] if the event class has no registered owner
      sig { params(event_class: T.class_of(Event)).returns(T.class_of(Aggregate)) }
      def self.owner_type_for(event_class)
        @owners.fetch(event_class)
      end

      register(event_class: Accounts::AccountCreated, aggregate_class: Accounts::Account)
    end
  end
end
