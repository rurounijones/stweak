# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../domain/aggregate'
require_relative '../../domain/checkpoint'
require_relative '../../domain/id'
require_relative '../../ports/checkpoint_store'

module Stweak
  module Adapters
    # Checkpoint store adapters.
    module CheckpointStore
      # An in-memory checkpoint store: the only implementation this phase.
      # Checkpoints do not survive a restart, which is accepted while nothing
      # else is persisted either; a durable checkpoint store is a deferred
      # item. Checkpoints are held per owner, where an owner is a type and an
      # id, so an Account and a Player that happen to share an id never
      # collide.
      class InMemoryCheckpointStore
        include Stweak::Ports::CheckpointStore

        extend T::Sig

        sig { void }
        def initialize
          @checkpoints = T.let(
            {},
            T::Hash[
              T.class_of(Stweak::Domain::Aggregate),
              T::Hash[Stweak::Domain::Id, Stweak::Domain::Checkpoint]
            ]
          )
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [Stweak::Domain::Id]
        # @return [Stweak::Domain::Checkpoint, nil] the checkpoint, or nil if
        #   the owner has none
        sig do
          override
            .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
            .returns(T.nilable(Stweak::Domain::Checkpoint))
        end
        def get(owner_type:, owner_id:)
          @checkpoints[owner_type]&.[](owner_id)
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [Stweak::Domain::Id]
        # @param checkpoint [Stweak::Domain::Checkpoint]
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              owner_id: Stweak::Domain::Id,
              checkpoint: Stweak::Domain::Checkpoint
            )
            .void
        end
        def put(owner_type:, owner_id:, checkpoint:)
          checkpoints_for_type = @checkpoints[owner_type]
          if checkpoints_for_type.nil?
            @checkpoints[owner_type] = T.let({}, T::Hash[Stweak::Domain::Id, Stweak::Domain::Checkpoint])
            checkpoints_for_type = T.must(@checkpoints[owner_type])
          end
          checkpoints_for_type[owner_id] = checkpoint
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [Stweak::Domain::Id]
        sig do
          override
            .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
            .void
        end
        def delete(owner_type:, owner_id:)
          @checkpoints[owner_type]&.delete(owner_id)
        end
      end
    end
  end
end
