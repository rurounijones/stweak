# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../../domain/event'
require_relative '../../domain/aggregate'
require_relative '../../domain/id'
require_relative '../../domain/owner_registry'
require_relative '../../domain/value_missing'
require_relative '../../ports/event_store'
require_relative '../../ports/key_store'
require_relative '../encryption/aes_gcm'

module Stweak
  module Adapters
    module EventStore
      # Decorates an event store with encryption of personal data. On append it
      # encrypts each PII field before persisting; on read it decrypts them
      # back. The domain emits and receives plaintext and never knows what
      # AES-256-GCM is. Keys are held per owner — a type and an id — created
      # implicitly on first use. When an owner's key is missing on read — it
      # was shredded under a GDPR erasure — the encrypted fields read back as
      # ValueMissing rather than raising: the data is gone by design, and that
      # is a normal state, not an error.
      #
      # rubocop:disable Metrics/ClassLength -- a decorator that both stores and
      # encrypts; the extra methods are the point of the encryption boundary.
      class EncryptingEventStore
        include Stweak::Ports::EventStore

        extend T::Sig

        # @param store [Stweak::Ports::EventStore] the store to decorate
        # @param cipher [Stweak::Adapters::Encryption::AesGcm]
        # @param key_store [Stweak::Ports::KeyStore]
        sig do
          params(
            store: Stweak::Ports::EventStore,
            cipher: Stweak::Adapters::Encryption::AesGcm,
            key_store: Stweak::Ports::KeyStore
          ).void
        end
        def initialize(store:, cipher:, key_store:)
          @store = store
          @cipher = cipher
          @key_store = key_store
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate
        #   class the stream belongs to
        # @param stream_id [String]
        # @param expected_version [Integer]
        # @param events [Array<Stweak::Domain::Event>]
        # @raise [Stweak::Ports::ConcurrencyError] from the underlying store
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              stream_id: Stweak::Domain::Id,
              expected_version: Integer,
              events: T::Array[Stweak::Domain::Event]
            )
            .void
        end
        def append(owner_type:, stream_id:, expected_version:, events:)
          @store.append(
            owner_type: owner_type,
            stream_id: stream_id,
            expected_version: expected_version,
            events: events.map { |event| encrypt(event) }
          )
        end

        # @param owner_type [Class<Stweak::Domain::Aggregate>] the aggregate
        #   class the stream belongs to
        # @param stream_id [String]
        # @param after [Integer] the exclusive lower bound on sequence; 0 reads
        #   the whole stream
        # @return [Array<Stweak::Domain::Event>]
        sig do
          override
            .params(
              owner_type: T.class_of(Stweak::Domain::Aggregate),
              stream_id: Stweak::Domain::Id,
              after: Integer
            )
            .returns(T::Array[Stweak::Domain::Event])
        end
        def read_stream(owner_type:, stream_id:, after: 0)
          @store.read_stream(owner_type: owner_type, stream_id: stream_id, after: after).map { |event| decrypt(event) }
        end

        # @yield [owner_type, stream_id, events]
        # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
        # anonymous `&`; the named block parameter is required to match the sig.
        sig do
          override
            .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                       stream_id: Stweak::Domain::Id,
                                       events: T::Array[Stweak::Domain::Event]).void)
            .void
        end
        def each_stream(&blk)
          @store.each_stream do |owner_type, stream_id, events|
            yield(owner_type, stream_id, events.map { |event| decrypt(event) })
          end
        end
        # rubocop:enable Naming/BlockForwarding

        private

        # A copy of the event with every PII field encrypted.
        #
        # @param event [Stweak::Domain::Event]
        # @return [Stweak::Domain::Event]
        sig { params(event: Stweak::Domain::Event).returns(Stweak::Domain::Event) }
        def encrypt(event)
          fields = event.class.pii_fields
          return event if fields.empty?

          key = key_for(owner_type: owner_for(event), owner_id: event.stream_id)
          operation = ->(value) { @cipher.encrypt(plaintext: value, key: key) }
          event.with(transform(event, fields, operation))
        end

        # A copy of the event with every PII field decrypted. If the owner's
        # key has been shredded, every PII field becomes ValueMissing instead:
        # the data is gone by design, which is a normal state, not an error.
        #
        # @param event [Stweak::Domain::Event]
        # @return [Stweak::Domain::Event]
        sig { params(event: Stweak::Domain::Event).returns(Stweak::Domain::Event) }
        def decrypt(event)
          fields = event.class.pii_fields
          return event if fields.empty?

          key = @key_store.get(owner_type: owner_for(event), owner_id: event.stream_id)
          return event.with(missing_fields(fields)) if key.nil?

          operation = ->(value) { @cipher.decrypt(ciphertext: value, key: key) }
          event.with(transform(event, fields, operation))
        end

        # A set of replacements turning every PII field into ValueMissing, for
        # when an owner's key is gone.
        #
        # @param fields [Array<Symbol>]
        # @return [Hash{String => Stweak::Domain::ValueMissing}]
        sig do
          params(fields: T::Array[Symbol])
            .returns(T::Hash[String, T.class_of(Stweak::Domain::ValueMissing)])
        end
        def missing_fields(fields)
          attributes = T.let({}, T::Hash[String, T.class_of(Stweak::Domain::ValueMissing)])
          fields.each { |field| attributes[field.to_s] = Stweak::Domain::ValueMissing }
          attributes
        end

        # The aggregate class that owns an event, looked up in the registry.
        #
        # @param event [Stweak::Domain::Event]
        # @return [Class<Stweak::Domain::Aggregate>]
        sig { params(event: Stweak::Domain::Event).returns(T.class_of(Stweak::Domain::Aggregate)) }
        def owner_for(event)
          Stweak::Domain::OwnerRegistry.owner_type_for(event.class)
        end

        # The key for an owner, generating and storing one on first use.
        #
        # @param owner_type [Class<Stweak::Domain::Aggregate>]
        # @param owner_id [String]
        # @return [String]
        sig { params(owner_type: T.class_of(Stweak::Domain::Aggregate), owner_id: Stweak::Domain::Id).returns(String) }
        def key_for(owner_type:, owner_id:)
          key = @key_store.get(owner_type: owner_type, owner_id: owner_id)
          return key unless key.nil?

          key = @cipher.generate_key
          @key_store.put(owner_type: owner_type, owner_id: owner_id, key: key)
          key
        end

        # Map each PII field name to the operation's result for that field's
        # value. The operation is passed as a callable rather than a block so
        # Sorbet can type it without the block-parameter special case.
        #
        # @param event [Stweak::Domain::Event]
        # @param fields [Array<Symbol>]
        # @param operation [Proc] takes a field value, returns its replacement
        # @return [Hash{String => String}]
        sig do
          params(
            event: Stweak::Domain::Event,
            fields: T::Array[Symbol],
            operation: T.proc.params(arg0: String).returns(String)
          ).returns(T::Hash[String, String])
        end
        def transform(event, fields, operation)
          attributes = T.let({}, T::Hash[String, String])
          fields.each do |field|
            attributes[field.to_s] = operation.call(event.public_send(field))
          end
          attributes
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
