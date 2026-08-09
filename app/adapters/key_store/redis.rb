# typed: strict
# frozen_string_literal: true

require 'redis'
require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    # A key store backed by Redis: the real, durable implementation of
    # Stweak::Ports::KeyStore, living alongside the domain gem's in-memory one
    # to prove the port is interchangeable. A key is stored raw under a key
    # qualified by the owner's class and id, so an Account and a Player that
    # happen to share an id never share a key. A missing key reads back as nil,
    # the same normal state the in-memory store presents for a shredded owner.
    class RedisKeyStore
      include Stweak::Ports::KeyStore

      extend T::Sig

      # @param redis [Redis] the client to use; the caller owns it and its
      #   lifecycle
      sig { params(redis: Redis).void }
      def initialize(redis:)
        @redis = redis
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      # @return [String, nil]
      sig do
        override
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(T.nilable(String))
      end
      def get(owner_type:, owner_id:)
        @redis.get(key_for(owner_type, owner_id))
      end

      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      # @param key [String]
      sig do
        override
          .params(
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            owner_id: Stweak::Domain::Id,
            key: String
          )
          .void
      end
      def put(owner_type:, owner_id:, key:)
        @redis.set(key_for(owner_type, owner_id), key)
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

      # The Redis key for an owner's key.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>]
      # @param owner_id [Stweak::Domain::Id]
      # @return [String]
      sig do
        params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(String)
      end
      def key_for(owner_type, owner_id)
        "key:#{owner_type.name}:#{owner_id}"
      end
    end
  end
end
