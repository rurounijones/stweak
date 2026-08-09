# typed: strict
# frozen_string_literal: true

require 'json'
require 'redis'
require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # A checkpoint store backed by Redis: the real, durable implementation of
    # Stweak::Ports::CheckpointStore, living alongside the domain gem's
    # in-memory one to prove the port is interchangeable. A checkpoint is
    # stored as JSON under a key qualified by the owner's class and id, so an
    # Account and a Player that happen to share an id never share a checkpoint.
    class RedisCheckpointStore
      include Stweak::Ports::CheckpointStore

      extend T::Sig

      # @param redis [Redis] the client to use; the caller owns it and its
      #   lifecycle
      sig { params(redis: Redis).void }
      def initialize(redis:)
        @redis = redis
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      # @return [Stweak::Domain::Checkpoint, nil]
      sig do
        override
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(T.nilable(Stweak::Domain::Checkpoint))
      end
      def get(owner_type:, owner_id:)
        stored = @redis.get(key_for(owner_type, owner_id))
        return nil if stored.nil?

        data = JSON.parse(stored)
        Stweak::Domain::Checkpoint.new(state: data.fetch('state'), version: data.fetch('version'))
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
        @redis.set(
          key_for(owner_type, owner_id),
          JSON.generate('state' => checkpoint.state, 'version' => checkpoint.version)
        )
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      sig do
        override
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .void
      end
      def delete(owner_type:, owner_id:)
        @redis.del(key_for(owner_type, owner_id))
      end

      private

      # The Redis key for an owner's checkpoint.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      # @return [String]
      sig do
        params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(String)
      end
      def key_for(owner_type, owner_id)
        "checkpoint:#{owner_type.name}:#{owner_id}"
      end
    end
  end
end
