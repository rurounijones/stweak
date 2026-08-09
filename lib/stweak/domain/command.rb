# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Domain
    # The base class for commands: requests for something to happen. A command
    # is an intention that may be rejected; an event is a fact that already
    # happened. Handling a command means validating it against current state
    # and, if it holds up, appending the events it produces.
    class Command
      extend T::Sig
      extend T::Helpers

      abstract!
    end
  end
end
