# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'stweak'

module App
  module Adapters
    module ProjectionStore
      # Decorates a projection store with encryption of personal data in the
      # read models it hosts, the projection-side mirror of the event store's
      # EncryptingEventStore. A projector writes plaintext — the account's
      # display name — and this decorator turns each declared PII column into
      # its cipher column before the row is persisted, keyed per owner exactly
      # as the event store keys it, so the same key protects the same person's
      # data everywhere. Erasure is crypto-shredding: delete the owner's key
      # and the ciphertext becomes unreadable. When an owner's key is missing
      # on read, the PII field reads back as ValueMissing rather than raising:
      # the data is gone by design, and that is a normal state, not an error.
      # Cursors contain no personal data, so the cursor operations pass through
      # untouched.
      #
      # rubocop:disable Metrics/ClassLength -- a decorator that both stores and
      # encrypts; the extra methods are the point of the encryption boundary.
      class EncryptingProjectionStore
        include Stweak::Ports::ProjectionStore

        extend T::Sig

        # The PII columns of each read-model table: for each, the plaintext
        # attribute a projector passes and the cipher column it is stored
        # under, plus the attribute naming the owner and the id type to rebuild
        # the owner's id for the key store.
        PII = T.let(
          {
            accounts: {
              columns: [
                { plaintext: :name, cipher: :name_cipher },
                { plaintext: :email, cipher: :email_cipher }
              ],
              owner_attribute: :account_id,
              owner_id_type: Stweak::Domain::Accounts::AccountId
            }
          }.freeze,
          T::Hash[Symbol, T.untyped]
        )

        # The marker stored in a PII column when the plaintext was already
        # missing — the owner's key was shredded before the row was written —
        # so no new key is minted for data that is gone by design.
        MISSING = T.let(Stweak::Domain::ValueMissing.name, String)

        # @param store [Stweak::Ports::ProjectionStore] the store to decorate
        # @param cipher [Stweak::Adapters::Encryption::AesGcm]
        # @param key_store [Stweak::Ports::KeyStore]
        # @param pii [Hash{Symbol => Object}] the PII columns of each read-model
        #   table; defaults to the accounts mapping, and can be supplied so a
        #   table without PII columns passes through untouched
        sig do
          params(
            store: Stweak::Ports::ProjectionStore,
            cipher: Stweak::Adapters::Encryption::AesGcm,
            key_store: Stweak::Ports::KeyStore,
            pii: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(store:, cipher:, key_store:, pii: PII)
          @store = store
          @cipher = cipher
          @key_store = key_store
          @pii = pii
        end

        # @param projection_name [String]
        # @return [Hash{String => Integer}, nil]
        sig { override.params(projection_name: String).returns(T.nilable(T::Hash[String, Integer])) }
        def read(projection_name:)
          @store.read(projection_name: projection_name)
        end

        # @param projection_name [String]
        # @param cursors [Hash{String => Integer}]
        sig { override.params(projection_name: String, cursors: T::Hash[String, Integer]).void }
        def write(projection_name:, cursors:)
          @store.write(projection_name: projection_name, cursors: cursors)
        end

        # @param projection_name [String]
        sig { override.params(projection_name: String).void }
        def delete(projection_name:)
          @store.delete(projection_name: projection_name)
        end

        # @param table [Symbol]
        # @param attributes [Hash{Symbol => Object}]
        sig { override.params(table: Symbol, attributes: T::Hash[Symbol, T.untyped]).void }
        def upsert(table:, attributes:)
          pii = @pii[table]
          return @store.upsert(table: table, attributes: attributes) if pii.nil?

          @store.upsert(table: table, attributes: encrypt(attributes, pii))
        end

        # @param table [Symbol]
        # @param id [String]
        sig { override.params(table: Symbol, id: String).void }
        def delete_row(table:, id:)
          @store.delete_row(table: table, id: id)
        end

        # @param table [Symbol]
        sig { override.params(table: Symbol).void }
        def clear(table:)
          @store.clear(table: table)
        end

        # @param table [Symbol]
        # @return [Array<Hash{Symbol => Object}>]
        sig { override.params(table: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def read_all(table:)
          pii = @pii[table]
          rows = @store.read_all(table: table)
          return rows if pii.nil?

          rows.map { |row| decrypt(row, pii) }
        end

        # @param table [Symbol]
        # @param id [String]
        # @return [Hash{Symbol => Object}, nil]
        sig { override.params(table: Symbol, id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def read_row(table:, id:)
          pii = @pii[table]
          row = @store.read_row(table: table, id: id)
          return row if pii.nil? || row.nil?

          decrypt(row, pii)
        end

        private

        # A copy of the row with every PII plaintext replaced by its encrypted
        # form under the owner's key. If a plaintext is already missing — the
        # owner's key was shredded before the event was projected — its cipher
        # column holds the MISSING marker instead, and no key is minted unless
        # at least one field is still worth encrypting.
        #
        # @param attributes [Hash{Symbol => Object}]
        # @param pii [Hash{Symbol => Object}]
        # @return [Hash{Symbol => Object}]
        sig { params(attributes: T::Hash[Symbol, T.untyped], pii: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def encrypt(attributes, pii)
          key = key_for(pii, attributes.fetch(pii.fetch(:owner_attribute))) if any_plaintext?(attributes, pii)
          pii.fetch(:columns).reduce(attributes) do |transformed, column|
            ciphertext = encrypt_value(attributes.fetch(column.fetch(:plaintext)), key)
            transformed.reject { |attribute, _| attribute == column.fetch(:plaintext) }
                       .merge(column.fetch(:cipher) => ciphertext)
          end
        end

        # A copy of the row with every cipher column decrypted back to its
        # plaintext attribute. A missing key — it was shredded under a GDPR
        # erasure — reads the fields back as ValueMissing.
        #
        # @param row [Hash{Symbol => Object}]
        # @param pii [Hash{Symbol => Object}]
        # @return [Hash{Symbol => Object}]
        sig { params(row: T::Hash[Symbol, T.untyped], pii: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def decrypt(row, pii)
          key = @key_store.get(
            owner_type: Stweak::Domain::Accounts::Account,
            owner_id: owner_id(pii, row.fetch(pii.fetch(:owner_attribute)))
          )
          pii.fetch(:columns).reduce(row) do |transformed, column|
            plaintext = decrypt_value(row.fetch(column.fetch(:cipher)), key)
            transformed.reject { |attribute, _| attribute == column.fetch(:cipher) }
                       .merge(column.fetch(:plaintext) => plaintext)
          end
        end

        # Whether any PII column carries a real plaintext, i.e. the owner's key
        # is still worth having. If every field is already missing, no key is
        # minted for data that is gone by design.
        #
        # @param attributes [Hash{Symbol => Object}]
        # @param pii [Hash{Symbol => Object}]
        # @return [Boolean]
        sig { params(attributes: T::Hash[Symbol, T.untyped], pii: T.untyped).returns(T::Boolean) }
        def any_plaintext?(attributes, pii)
          pii.fetch(:columns).any? do |column|
            attributes.fetch(column.fetch(:plaintext)) != Stweak::Domain::ValueMissing
          end
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

        # The plaintext behind one cipher column: the MISSING marker for data
        # that was already gone when written, ValueMissing for a shredded key —
        # the data is gone by design, a normal state — or the decrypted value.
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

        # The owner's id, rebuilt from the value stored in the row, so the key
        # store finds the same key the event store created.
        #
        # @param pii [Hash{Symbol => Object}]
        # @param value [String]
        # @return [Stweak::Domain::Id]
        sig { params(pii: T.untyped, value: String).returns(Stweak::Domain::Id) }
        def owner_id(pii, value)
          pii.fetch(:owner_id_type).new(value: value)
        end

        # The key for an owner, generating and storing one on first use.
        #
        # @param pii [Hash{Symbol => Object}]
        # @param owner_id [String]
        # @return [String]
        sig { params(pii: T.untyped, owner_id: String).returns(String) }
        def key_for(pii, owner_id)
          id = owner_id(pii, owner_id)
          key = @key_store.get(owner_type: Stweak::Domain::Accounts::Account, owner_id: id)
          return key unless key.nil?

          key = @cipher.generate_key
          @key_store.put(owner_type: Stweak::Domain::Accounts::Account, owner_id: id, key: key)
          key
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
