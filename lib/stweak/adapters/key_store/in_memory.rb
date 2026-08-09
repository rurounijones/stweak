# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../domain/aggregate'
require_relative '../../domain/id'
require_relative '../../ports/key_store'

module Stweak
  module Adapters
    # Key store adapters.
    module KeyStore
      # An in-memory key store: the counterpart to the durable Redis one,
      # proving the port is interchangeable. A key is copied in on write and
      # copied out on read, so the store never shares a String object with the
      # caller — the round-trip the Redis store gets from copying the bytes into
      # Redis and reading a fresh String back. A raw key is binary rather than
      # text, so the copy is a dup rather than a codec. Nothing survives a
      # restart. Keys are held per owner, where an owner is a type and an id, so
      # an Account and a Player that happen to share an id never collide.
      class InMemoryKeyStore
        include Stweak::Ports::KeyStore

        extend T::Sig

        sig { void }
        def initialize
          @keys = T.let({}, T::Hash[T.class_of(Stweak::Domain::Aggregate), T::Hash[Stweak::Domain::Id, String]])
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [String]
        # @return [String, nil] the key, or nil if the owner has none
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              owner_id: Stweak::Domain::Id
            )
            .returns(T.nilable(String))
        end
        def get(owner_type:, owner_id:)
          @keys[owner_type]&.[](owner_id)&.dup
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [String]
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
          keys_for_type = @keys[owner_type]
          if keys_for_type.nil?
            @keys[owner_type] = T.let({}, T::Hash[Stweak::Domain::Id, String])
            keys_for_type = T.must(@keys[owner_type])
          end
          keys_for_type[owner_id] = key.dup
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [String]
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              owner_id: Stweak::Domain::Id
            )
            .void
        end
        def delete(owner_type:, owner_id:)
          @keys[owner_type]&.delete(owner_id)
        end
      end
    end
  end
end
