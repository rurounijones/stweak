# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'event'

module Stweak
  module Domain
    # The contract a projection — in the standard event-sourcing vocabulary, a
    # *projector* — implements: it folds the events it cares about into a
    # materialized read model and ignores the rest, so it can be replayed over
    # a full log without tripping on events that belong to other aggregates.
    # The event log is the source of truth: a projection is derived data, and
    # it can be discarded and rebuilt from the log at any time.
    #
    # Subclasses implement #apply to fold one event in and #reset to return the
    # read model to the empty state. The projection's materialized state is not
    # a serializable value that the projection holds: it is the rows the
    # projection writes, through the projection store, as it applies events. The
    # projection system drives #apply and #reset and keeps the projection's
    # per-stream cursors durable.
    class Projection
      extend T::Sig
      extend T::Helpers

      abstract!

      # The projection's stable name: the key its cursors are stored under, so
      # the projection system can persist and reload them.
      #
      # @return [String]
      sig { returns(String) }
      def name
        self.class.to_s.split('::').fetch(-1)
      end

      # Fold one event into the read model. Subclasses implement, ignoring
      # events they do not care about so that a full-log replay is safe.
      #
      # @param event [Event]
      sig { abstract.params(event: Event).void }
      def apply(event); end

      # Return the read model to the empty state it had before any event was
      # applied. Called by the projection system when a projection is rebuilt
      # from the beginning of the log.
      sig { abstract.void }
      def reset; end
    end
  end
end
