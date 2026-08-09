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
      # An in-memory checkpoint store: the counterpart to the durable Redis one,
      # proving the port is interchangeable. Rather than holding the live
      # Checkpoint, it holds a detached snapshot of the checkpoint's state and
      # version and rebuilds a fresh Checkpoint on read, so it round-trips
      # through the checkpoint's serialized form exactly as the Redis store
      # round-trips it through JSON: only plain data survives, and a caller can
      # neither see the stored object nor reach in and mutate it. Nothing
      # survives a restart. Checkpoints are held per owner, where an owner is a
      # type and an id, so an Account and a Player that happen to share an id
      # never collide.
      class InMemoryCheckpointStore
        include Stweak::Ports::CheckpointStore

        extend T::Sig

        # A stored checkpoint: a detached copy of its state and its version.
        # Holding the serialized state rather than the live Checkpoint makes the
        # store round-trip through serialization on read, exactly as the durable
        # store does.
        Stored = T.type_alias { [T::Hash[String, T.untyped], Integer] }

        sig { void }
        def initialize
          @checkpoints = T.let(
            {},
            T::Hash[T.class_of(Stweak::Domain::Aggregate), T::Hash[Stweak::Domain::Id, Stored]]
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
          stored = @checkpoints[owner_type]&.[](owner_id)
          return nil if stored.nil?

          state, version = stored
          Stweak::Domain::Checkpoint.new(state: deep_dup(state), version: version)
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
            @checkpoints[owner_type] = T.let({}, T::Hash[Stweak::Domain::Id, Stored])
            checkpoints_for_type = T.must(@checkpoints[owner_type])
          end
          checkpoints_for_type[owner_id] = [deep_dup(checkpoint.state), checkpoint.version]
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

        private

        # A deep copy of a plain-data value, so the stored snapshot shares no
        # mutable structure with the caller's state and each read hands back a
        # fresh one — the detachment the durable store gets from its JSON
        # round-trip.
        #
        # @param value [Object]
        # @return [Object]
        sig { params(value: T.untyped).returns(T.untyped) }
        def deep_dup(value)
          case value
          when Hash then value.transform_values { |element| deep_dup(element) }
          when Array then value.map { |element| deep_dup(element) }
          else value
          end
        end
      end
    end
  end
end
