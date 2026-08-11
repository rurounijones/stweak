# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Domain
    # The base class for every error the domain raises. Naming the categories
    # below is what "Errors are part of the contract" in the design decisions
    # means in practice: a caller — a future CLI or HTTP adapter — can rescue
    # this base for any domain failure, or rescue a category to tell validation
    # from not-found from conflict without parsing messages.
    #
    # Errors here are reserved for genuine failures — something that should not
    # have happened given the rules — and are never used to steer control flow.
    # Deliberately absent is a category for "an event an aggregate does not
    # know": that is a corrupt-stream or history-mismatch bug, raised as
    # ArgumentError at the apply site, not a condition a caller is expected to
    # handle.
    class Error < StandardError; end

    # A command, value object, or event was malformed and refused at
    # construction. An invalid object cannot come into existence.
    class ValidationError < Error; end

    # Something that was looked up does not exist.
    class NotFoundError < Error; end

    # A well-formed command was rejected against current state: the change
    # conflicts with an invariant, such as creating an account that already
    # exists or appending to a stream that has moved on.
    class ConflictError < Error; end
  end
end
