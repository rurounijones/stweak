# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../domain/aggregate'
require_relative '../domain/id'

module Stweak
  module Ports
    # The port a key store implements: storage of encryption keys, keyed by the
    # owner that holds them. An owner is an aggregate class and an id, because
    # the project cannot assume that different kinds of owner — an Account, a
    # Player — have globally unique ids; they may come from separate stores
    # each numbering their own rows from one. Qualifying the key with the
    # owner's class keeps an Account and a Player that happen to share an id
    # from ever sharing, or shredding, a key. Crypto-shredding's "erasure is
    # deleting the key" depends on a key store that can be deleted from, which
    # is why keys live in mutable storage outside the event log.
    module KeyStore
      extend T::Sig
      extend T::Helpers

      interface!

      # Get the key for an owner, or nil if the owner has none. A missing key
      # is a normal result, not an error: under crypto-shredding an owner's key
      # may have been deleted to erase their personal data, in which case the
      # data is unreadable by design and there is no key to return.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   that owns the data, such as Account
      # @param owner_id [Stweak::Domain::Id] the owner's id within its own kind
      # @return [String, nil] the key, 32 raw bytes, or nil if the owner has
      #   none
      sig do
        abstract
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id)
          .returns(T.nilable(String))
      end
      def get(owner_type:, owner_id:); end

      # Store a key for an owner, replacing any key they already have.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   that owns the data, such as Account
      # @param owner_id [Stweak::Domain::Id] the owner's id within its own kind
      # @param key [String]
      sig do
        abstract
          .params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id, key: String)
          .void
      end
      def put(owner_type:, owner_id:, key:); end

      # Delete the key for an owner. Deleting a missing key does not raise.
      #
      # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate class
      #   that owns the data, such as Account
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
