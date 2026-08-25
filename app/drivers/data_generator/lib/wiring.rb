# typed: strict
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'aws-sdk-sqs'
require 'redis'
require 'sqlite3'
require 'sorbet-runtime'
require 'stweak'
require_relative '../../../adapters/event_store/dynamo_db'
require_relative '../../../adapters/projection_store/sqlite'
require_relative '../../../adapters/projection_store/encrypting'
require_relative '../../../adapters/projection/accounts_projector'
require_relative '../../../adapters/projection/usernames'
require_relative '../../../adapters/checkpoint_store/redis'
require_relative '../../../adapters/checkpoint_store/encrypting'
require_relative '../../../adapters/key_store/redis'
require_relative '../../../adapters/event_subscription/elastic_mq'
require_relative '../../../adapters/security/bcrypt_password_hasher'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative 'data_generator'

module DataGenerator
  # The composition root: assembles the domain with the real adapters so the
  # generator drives the actual system — DynamoDB event store wrapped in the
  # encrypting store (Redis keys), ElasticMQ subscription feeding the SQLite
  # projection store, Redis checkpoint store, bcrypt hasher — rather than the
  # in-memory stand-ins. It is the one place the adapters meet.
  class Wiring
    extend T::Sig

    # The assembled system a caller drives: the generator, plus the subscription
    # so a short-lived caller can drain the read side before it exits. Delivery
    # to the projections is asynchronous through the subscription's queue, so
    # without draining a run can exit with events still unconsumed.
    class Built < T::Struct
      const :generator, DataGenerator::Generator
      const :subscription, App::Adapters::ElasticMqSubscription
    end

    # Build the wiring.
    #
    # @param database_path [String] the SQLite file for the projection store
    # @param streams_table [String] the DynamoDB streams table name
    # @param queue_name [String] the ElasticMQ queue name
    # @return [DataGenerator::Wiring::Built]
    # rubocop:disable Metrics/MethodLength -- one composition step: the read
    # side, the handler over it, and the pair the caller drives and drains.
    sig do
      params(
        database_path: String,
        streams_table: String,
        queue_name: String
      ).returns(Built)
    end
    def self.build(database_path:, streams_table:, queue_name:)
      event_store, usernames, subscription = build_read_side(database_path:, streams_table:, queue_name:)
      handler = Stweak::Domain::Accounts::CreateAccountHandler.new(
        event_store: event_store,
        password_hasher: App::Adapters::BcryptPasswordHasher.new,
        checkpoint_store: encrypted_checkpoint_store,
        usernames: usernames
      )
      Built.new(
        generator: DataGenerator::Generator.new(handler: handler, event_store: event_store),
        subscription: subscription
      )
    end
    # rubocop:enable Metrics/MethodLength

    # The read side: the event store (DynamoDB behind the encrypting store,
    # keys in Redis) publishing through the subscription, and the accounts
    # projector fed by a projection system into the SQLite projection store
    # behind the encrypting decorator (Redis keys). Returns the store and the
    # usernames read so the write side can share them, and the subscription so
    # the caller can drain it.
    #
    # @param database_path [String] the SQLite file for the projection store
    # @param streams_table [String] the DynamoDB streams table name
    # @param queue_name [String] the ElasticMQ queue name
    # @return [Array(Stweak::Ports::EventStore, Stweak::Ports::Usernames, App::Adapters::ElasticMqSubscription)]
    sig do
      params(
        database_path: String,
        streams_table: String,
        queue_name: String
      ).returns([Stweak::Ports::EventStore, Stweak::Ports::Usernames, App::Adapters::ElasticMqSubscription])
    end
    def self.build_read_side(database_path:, streams_table:, queue_name:)
      key_store = App::Adapters::RedisKeyStore.new(redis: redis)
      raw_projection_store = App::Adapters::SqliteProjectionStore.new(
        db: SQLite3::Database.new(database_path)
      )
      projection_store = encrypted_projection_store(key_store, raw_projection_store)
      subscription = App::Adapters::ElasticMqSubscription.new(sqs: sqs, queue_name: queue_name)
      event_store = encrypting_store(key_store, subscription, streams_table)
      projection_system = Stweak::Domain::ProjectionSystem.new(
        event_store: event_store, projection_store: projection_store, subscription: subscription
      )
      projection = App::Adapters::Projection::AccountsProjector.new(store: projection_store)
      projection_system.register_with(
        projection,
        stream_reader: event_store.method(:each_encrypted_stream),
        event_applier: projection.method(:apply_encrypted)
      )
      # Username uniqueness only needs the non-PII username column. Reading it
      # through the encrypting decorator would decrypt every account row and
      # issue one Redis key lookup per row on every create.
      usernames = App::Adapters::Projection::Usernames.new(store: raw_projection_store)
      [event_store, usernames, subscription]
    end

    # The encrypting projection store: the SQLite store behind the encrypting
    # decorator, keys in Redis, so the account name is encrypted at the store
    # boundary.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @param store [Stweak::Ports::ProjectionStore]
    # @return [Stweak::Ports::ProjectionStore]
    sig do
      params(key_store: Stweak::Ports::KeyStore, store: Stweak::Ports::ProjectionStore)
        .returns(Stweak::Ports::ProjectionStore)
    end
    def self.encrypted_projection_store(key_store, store)
      App::Adapters::ProjectionStore::EncryptingProjectionStore.new(
        store: store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store
      )
    end

    # The encrypting checkpoint store: the Redis checkpoint store behind the
    # encrypting decorator, keys in Redis, so the account state a checkpoint
    # caches — its display name and email — is encrypted at the store boundary.
    # The key store reaches the same Redis key namespace as the event and
    # projection stores', so one shred erases a person's data everywhere.
    #
    # @return [Stweak::Ports::CheckpointStore]
    sig { returns(Stweak::Ports::CheckpointStore) }
    def self.encrypted_checkpoint_store
      App::Adapters::CheckpointStore::EncryptingCheckpointStore.new(
        store: App::Adapters::RedisCheckpointStore.new(redis: redis),
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: App::Adapters::RedisKeyStore.new(redis: redis)
      )
    end

    # The encrypting event store: the DynamoDB store behind the encrypting
    # decorator, publishing plaintext through the subscription and keeping its
    # keys in Redis.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @param subscription [Stweak::Ports::EventSubscription]
    # @param streams_table [String]
    # @return [Stweak::Ports::EventStore]
    sig do
      params(
        key_store: Stweak::Ports::KeyStore,
        subscription: Stweak::Ports::EventSubscription,
        streams_table: String
      ).returns(Stweak::Ports::EventStore)
    end
    def self.encrypting_store(key_store, subscription, streams_table)
      store = App::Adapters::DynamoDBEventStore.new(
        client: dynamo, streams_table: streams_table
      )
      Stweak::Adapters::EventStore::EncryptingEventStore.new(
        store: store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store,
        subscription: subscription
      )
    end

    # The DynamoDB client, from the environment (compose service name in the
    # dev container, localhost in CI).
    #
    # @return [Aws::DynamoDB::Client]
    sig { returns(Aws::DynamoDB::Client) }
    def self.dynamo
      Aws::DynamoDB::Client.new(
        endpoint: ENV.fetch('AWS_ENDPOINT_URL', 'http://localhost:8000'),
        region: 'us-east-1',
        credentials: Aws::Credentials.new('dummy', 'dummy')
      )
    end

    # The SQS client, from the environment.
    #
    # @return [Aws::SQS::Client]
    sig { returns(Aws::SQS::Client) }
    def self.sqs
      Aws::SQS::Client.new(
        endpoint: ENV.fetch('ELASTICMQ_URL', 'http://localhost:9324'),
        region: 'us-east-1',
        credentials: Aws::Credentials.new('dummy', 'dummy')
      )
    end

    # The Redis client, from the environment.
    #
    # @return [Redis]
    sig { returns(Redis) }
    def self.redis
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
    end
  end
end
