# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    module CheckpointStore
      # Decorates a checkpoint store with encryption of the personal data in the
      # aggregate state it caches, the checkpoint-side mirror of the event
      # store's EncryptingEventStore. An aggregate writes plaintext — the
      # account's display name and email — into its checkpoint_state, and this
      # decorator encrypts each key the aggregate declares as PII before the
      # checkpoint is persisted, keyed per owner exactly as the event store keys
      # it, so the same key protects the same person's data everywhere. Erasure
      # is crypto-shredding: delete the owner's key and the ciphertext becomes
      # unreadable. When an owner's key is missing on read, the PII keys read
      # back as ValueMissing rather than raising: the data is gone by design,
      # and that is a normal state, not an error.
      #
      # Which keys are PII is the aggregate's own declaration —
      # owner_type.checkpoint_pii_fields — because the checkpoint state is the
      # aggregate's serialization of itself and the PII declaration is a domain
      # business rule. An owner with no such keys passes through untouched.
      #
      # Sitting above the store it decorates, it only ever hands the store
      # ciphertext or marker strings for the PII keys, never a ValueMissing
      # class, so a JSON-backed store serializes without knowing any of this.
      #
      # rubocop:disable Metrics/ClassLength -- a decorator that both stores and
      # encrypts; the extra methods are the point of the encryption boundary.
      class EncryptingCheckpointStore
        include Stweak::Ports::CheckpointStore

        extend T::Sig

        # The marker stored in a PII key when the plaintext was already missing
        # — the owner's key was shredded before the checkpoint was taken — so no
        # new key is minted for data that is gone by design.
        MISSING = T.let(Stweak::Domain::ValueMissing.name, String)

        # @param store [Stweak::Ports::CheckpointStore] the store to decorate
        # @param cipher [Stweak::Adapters::Encryption::AesGcm]
        # @param key_store [Stweak::Ports::KeyStore]
        sig do
          params(
            store: Stweak::Ports::CheckpointStore,
            cipher: Stweak::Adapters::Encryption::AesGcm,
            key_store: Stweak::Ports::KeyStore
          ).void
        end
        def initialize(store:, cipher:, key_store:)
          @store = store
          @cipher = cipher
          @key_store = key_store
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
          checkpoint = @store.get(owner_type: owner_type, owner_id: owner_id)
          fields = owner_type.checkpoint_pii_fields
          return checkpoint if checkpoint.nil? || fields.empty?

          key = @key_store.get(owner_type: owner_type, owner_id: owner_id)
          Stweak::Domain::Checkpoint.new(state: decrypt(checkpoint.state, fields, key), version: checkpoint.version)
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
          fields = owner_type.checkpoint_pii_fields
          return @store.put(owner_type: owner_type, owner_id: owner_id, checkpoint: checkpoint) if fields.empty?

          state = encrypt(checkpoint.state, fields, owner_type, owner_id)
          @store.put(
            owner_type: owner_type,
            owner_id: owner_id,
            checkpoint: Stweak::Domain::Checkpoint.new(state: state, version: checkpoint.version)
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
          @store.delete(owner_type: owner_type, owner_id: owner_id)
        end

        private

        # A copy of the state with every PII key replaced by its encrypted form
        # under the owner's key. If a value is already missing — the owner's key
        # was shredded before the checkpoint was taken — its key holds the
        # MISSING marker instead, and no key is minted unless at least one PII
        # value is still worth encrypting.
        #
        # @param state [Hash{String => Object}]
        # @param fields [Array<Symbol>]
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [Stweak::Domain::Id]
        # @return [Hash{String => Object}]
        sig do
          params(
            state: T::Hash[String, T.untyped],
            fields: T::Array[Symbol],
            owner_type: T.class_of(Stweak::Domain::Aggregate),
            owner_id: Stweak::Domain::Id
          ).returns(T::Hash[String, T.untyped])
        end
        def encrypt(state, fields, owner_type, owner_id)
          key = key_for(owner_type, owner_id) if any_plaintext?(state, fields)
          fields.reduce(state) do |transformed, field|
            transformed.merge(field.to_s => encrypt_value(state.fetch(field.to_s), key))
          end
        end

        # A copy of the state with every PII key decrypted back to its
        # plaintext. A missing key — it was shredded under a GDPR erasure —
        # reads the fields back as ValueMissing.
        #
        # @param state [Hash{String => Object}]
        # @param fields [Array<Symbol>]
        # @param key [String, nil]
        # @return [Hash{String => Object}]
        sig do
          params(state: T::Hash[String, T.untyped], fields: T::Array[Symbol], key: T.nilable(String))
            .returns(T::Hash[String, T.untyped])
        end
        def decrypt(state, fields, key)
          fields.reduce(state) do |transformed, field|
            transformed.merge(field.to_s => decrypt_value(state.fetch(field.to_s), key))
          end
        end

        # Whether any PII key carries a real plaintext, i.e. the owner's key is
        # still worth having. If every field is already missing, no key is
        # minted for data that is gone by design.
        #
        # @param state [Hash{String => Object}]
        # @param fields [Array<Symbol>]
        # @return [Boolean]
        sig { params(state: T::Hash[String, T.untyped], fields: T::Array[Symbol]).returns(T::Boolean) }
        def any_plaintext?(state, fields)
          fields.any? { |field| state.fetch(field.to_s) != Stweak::Domain::ValueMissing }
        end

        # The encrypted form of one plaintext: the MISSING marker for data that
        # was already gone when written, otherwise the value under the owner's
        # key.
        #
        # @param plaintext [Object]
        # @param key [String, nil]
        # @return [String]
        sig { params(plaintext: T.untyped, key: T.nilable(String)).returns(String) }
        def encrypt_value(plaintext, key)
          return MISSING if plaintext == Stweak::Domain::ValueMissing

          @cipher.encrypt(plaintext: plaintext, key: T.must(key))
        end

        # The plaintext behind one PII key: the MISSING marker for data that was
        # already gone when written, ValueMissing for a shredded key — the data
        # is gone by design, a normal state — or the decrypted value.
        #
        # @param ciphertext [String]
        # @param key [String, nil]
        # @return [String, Class<Stweak::Domain::ValueMissing>]
        sig do
          params(ciphertext: String, key: T.nilable(String))
            .returns(T.any(String, T.class_of(Stweak::Domain::ValueMissing)))
        end
        def decrypt_value(ciphertext, key)
          return Stweak::Domain::ValueMissing if ciphertext == MISSING

          key.nil? ? Stweak::Domain::ValueMissing : @cipher.decrypt(ciphertext: ciphertext, key: key)
        end

        # The key for an owner, generating and storing one on first use.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [Stweak::Domain::Id]
        # @return [String]
        sig { params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id).returns(String) }
        def key_for(owner_type, owner_id)
          key = @key_store.get(owner_type: owner_type, owner_id: owner_id)
          return key unless key.nil?

          key = @cipher.generate_key
          @key_store.put(owner_type: owner_type, owner_id: owner_id, key: key)
          key
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
