# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/aggregate'
require_relative '../domain/checkpoint'
require_relative '../domain/id'

module Stweak
  module Ports
    # The port a checkpoint store implements: storage of cached aggregate
    # state, keyed by the owner it belongs to. An owner is an aggregate class
    # and an id, for the same reason keys are qualified that way: the project
    # cannot assume that different kinds of owner — an Account, a Player —
    # have globally unique ids, so an Account and a Player that happen to share
    # an id must not share a checkpoint.
    #
    # A checkpoint is a cached copy of an aggregate's state at a point in its
    # stream, written by the write side every 100 events so that a command
    # handler can resume an aggregate from a checkpoint plus only the events
    # after it, rather than by replaying the whole stream. The store is
    # deliberately decoupled from projections: it tracks nothing about what has
    # been projected, and the cadence of checkpointing is the write side's
    # policy, not the store's. A checkpoint is derived data — the event log
    # remains the source of truth, and any checkpoint can be discarded and
    # rebuilt.
    module CheckpointStore
      extend T::Sig
      extend T::Helpers

      interface!

      # Get the checkpoint for an owner, or nil if the owner has none. A
      # missing checkpoint is a normal result, not an error: the write side
      # simply replays the whole stream.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   the checkpoint belongs to, such as Account
      # @param owner_id [Stweak::Domain::Id] the owner's id within its own kind
      # @return [Stweak::Domain::Checkpoint, nil] the checkpoint, or nil if the
      #   owner has none
      sig do
        abstract
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(T.nilable(Stweak::Domain::Checkpoint))
      end
      def get(owner_type:, owner_id:); end

      # Store a checkpoint for an owner, replacing any checkpoint they already
      # have.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   the checkpoint belongs to, such as Account
      # @param owner_id [Stweak::Domain::Id] the owner's id within its own kind
      # @param checkpoint [Stweak::Domain::Checkpoint] the checkpoint to store
      sig do
        abstract
          .params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            owner_id: Stweak::Domain::Id,
            checkpoint: Stweak::Domain::Checkpoint
          )
          .void
      end
      def put(owner_type:, owner_id:, checkpoint:); end

      # Delete the checkpoint for an owner. Deleting a missing checkpoint does
      # not raise.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   the checkpoint belongs to, such as Account
      # @param owner_id [Stweak::Domain::Id] the owner's id within its own kind
      sig do
        abstract
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .void
      end
      def delete(owner_type:, owner_id:); end
    end
  end
end
