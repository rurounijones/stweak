# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/event'

module Stweak
  module Ports
    # The interface a consumer of the event log implements to react to appends.
    # An event subscription delivers appended events to its listeners by
    # calling this. In memory the delivery is a synchronous callback; in
    # production the same contract would be met by a transport such as an SQS
    # queue delivering events out of process. A projection system is the
    # natural implementor.
    module EventStoreListener
      extend T::Sig
      extend T::Helpers

      interface!

      # Called after events have been appended.
      #
      # @param events [Array<Stweak::Domain::Event>] the appended events, in
      #   append order
      sig { abstract.params(events: T::Array[Stweak::Domain::Event]).void }
      def on_events_appended(events:); end
    end
  end
end
