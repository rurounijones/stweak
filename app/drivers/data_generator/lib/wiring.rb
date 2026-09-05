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
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/checkpoint_store/in_memory'
require_relative '../../../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative 'data_generator'
require_relative 'lifecycle_generator'

module DataGenerator
  # The composition root: it reads the adapter selection from the environment
  # (populated from the shared drivers .env; see ../../.env.example) and
  # assembles the domain with the chosen adapters so the generator drives the
  # actual system. Each collaborator has its own selector defaulting to the
  # real technology, so the generator runs against DynamoDB, ElasticMQ, SQLite
  # and Redis by default, or entirely in memory when every selector says so.
  # dotenv populates ENV; this class still reads ENV.fetch, so only the source
  # of the vars is new, not the way they are read. It is the one place the
  # adapters meet.
  #
  # rubocop:disable Metrics/ClassLength -- a composition root that wires the
  # whole write side: a selector per collaborator and an encrypting wrapper
  # for each store. The methods are the point, not incidental length.
  class Wiring
    extend T::Sig

    # Raised when a selector names an adapter that does not exist.
    class UnknownAdapter < StandardError; end

    # The assembled system a caller drives: the bounded create-only generator,
    # the continuous lifecycle generator, plus the subscription so a
    # short-lived caller can drain the read side before it exits. Delivery to
    # the projections is asynchronous through the subscription's transport, so
    # without draining a run can exit with events still unconsumed — their
    # projection work never done and, with tracing on, their spans never
    # recorded.
    class Built < T::Struct
      const :generator, DataGenerator::Generator
      const :lifecycle_generator, DataGenerator::LifecycleGenerator
      const :subscription, Stweak::Ports::EventSubscription
    end

    # Build the generators over the selected adapters. The one key store is
    # shared by every encrypting decorator — event store, projection store and
    # checkpoint store alike — so a single key decrypts a person's data
    # everywhere, and one shred erases it everywhere. Returns the generators
    # paired with the subscription so the caller can drain the read side.
    #
    # The method assembles every handler and store into one composite; a
    # reader follows that wiring top to bottom, so it deliberately exceeds the
    # default size and branch budgets rather than split the narrative.
    # @return [DataGenerator::Wiring::Built]
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    sig { returns(Built) }
    def self.build
      key_store = build_key_store
      subscription = build_subscription
      event_store = build_event_store(key_store, subscription)
      raw_projection = raw_projection_store
      projection_store = build_projection_store(key_store, raw_projection)
      register_projection(event_store, projection_store, subscription)
      handler = build_handler(event_store, raw_projection, key_store)
      checkpoint_store = build_checkpoint_store(key_store)
      disable_handler = Stweak::Domain::Accounts::DisableAccountHandler.new(
        event_store: event_store, checkpoint_store: checkpoint_store
      )
      delete_handler = Stweak::Domain::Accounts::DeleteAccountHandler.new(
        event_store: event_store, checkpoint_store: checkpoint_store
      )
      generator = DataGenerator::Generator.new(handler: handler, event_store: event_store)
      lifecycle_generator = DataGenerator::LifecycleGenerator.new(
        create_handler: handler, disable_handler: disable_handler, delete_handler: delete_handler
      )
      Built.new(generator: generator, lifecycle_generator: lifecycle_generator, subscription: subscription)
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    # The write-side command handler: it hashes through bcrypt, checkpoints to
    # the selected checkpoint store, and enforces username uniqueness against
    # the usernames read model. That check reads the raw, undecorated projection
    # store rather than the encrypting decorator: the username is a non-PII
    # column, so reading it directly answers the uniqueness question without
    # decrypting every account's name and email — the wasted work, and the key
    # fetch per row, that decrypting the whole table for one plaintext column
    # would cost.
    #
    # @param event_store [Stweak::Ports::EventStore]
    # @param raw_projection_store [Stweak::Ports::ProjectionStore] the
    #   undecorated store the accounts projector writes behind its encrypting
    #   decorator; shared so the username read sees the same rows
    # @param key_store [Stweak::Ports::KeyStore]
    # @return [Stweak::Domain::Accounts::CreateAccountHandler]
    sig do
      params(
        event_store: Stweak::Ports::EventStore,
        raw_projection_store: Stweak::Ports::ProjectionStore,
        key_store: Stweak::Ports::KeyStore
      ).returns(Stweak::Domain::Accounts::CreateAccountHandler)
    end
    def self.build_handler(event_store, raw_projection_store, key_store)
      Stweak::Domain::Accounts::CreateAccountHandler.new(
        event_store: event_store,
        password_hasher: App::Adapters::BcryptPasswordHasher.new,
        checkpoint_store: build_checkpoint_store(key_store),
        usernames: App::Adapters::Projection::Usernames.new(store: raw_projection_store)
      )
    end

    # Register the accounts projector on the subscription, so every append
    # feeds the projection store the generator later reads back.
    #
    # @param event_store [Stweak::Ports::EventStore]
    # @param projection_store [Stweak::Ports::ProjectionStore]
    # @param subscription [Stweak::Ports::EventSubscription]
    sig do
      params(
        event_store: Stweak::Ports::EventStore,
        projection_store: Stweak::Ports::ProjectionStore,
        subscription: Stweak::Ports::EventSubscription
      ).void
    end
    def self.register_projection(event_store, projection_store, subscription)
      system = Stweak::Domain::ProjectionSystem.new(
        event_store: event_store, projection_store: projection_store, subscription: subscription
      )
      system.register(App::Adapters::Projection::AccountsProjector.new(store: projection_store))
    end

    # The key store, from KEY_STORE.
    #
    # @return [Stweak::Ports::KeyStore]
    sig { returns(Stweak::Ports::KeyStore) }
    def self.build_key_store
      selection = ENV.fetch('KEY_STORE', 'redis')
      case selection
      when 'redis' then App::Adapters::RedisKeyStore.new(redis: redis)
      when 'memory' then Stweak::Adapters::KeyStore::InMemoryKeyStore.new
      else raise UnknownAdapter, "unknown KEY_STORE #{selection}"
      end
    end

    # The subscription, from SUBSCRIPTION: the transport that carries appended
    # events to the projector.
    #
    # @return [Stweak::Ports::EventSubscription]
    sig { returns(Stweak::Ports::EventSubscription) }
    def self.build_subscription
      selection = ENV.fetch('SUBSCRIPTION', 'elasticmq')
      case selection
      when 'elasticmq' then App::Adapters::ElasticMqSubscription.new(sqs: sqs, queue_name: queue_name)
      when 'memory' then Stweak::Adapters::EventSubscription::InMemoryEventSubscription.new
      else raise UnknownAdapter, "unknown SUBSCRIPTION #{selection}"
      end
    end

    # The event store, behind the encrypting decorator; it publishes plaintext
    # to the subscription and keeps its keys in the shared key store.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @param subscription [Stweak::Ports::EventSubscription]
    # @return [Stweak::Ports::EventStore]
    sig do
      params(key_store: Stweak::Ports::KeyStore, subscription: Stweak::Ports::EventSubscription)
        .returns(Stweak::Ports::EventStore)
    end
    def self.build_event_store(key_store, subscription)
      Stweak::Adapters::EventStore::EncryptingEventStore.new(
        store: raw_event_store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store,
        subscription: subscription
      )
    end

    # The projection store, behind the encrypting decorator so display names
    # and emails are encrypted at the store boundary. The undecorated store is
    # passed in rather than built here, so the same instance backs both the
    # decorator the projector writes through and the raw read the username
    # uniqueness check uses.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @param store [Stweak::Ports::ProjectionStore] the undecorated store to wrap
    # @return [Stweak::Ports::ProjectionStore]
    sig do
      params(key_store: Stweak::Ports::KeyStore, store: Stweak::Ports::ProjectionStore)
        .returns(Stweak::Ports::ProjectionStore)
    end
    def self.build_projection_store(key_store, store)
      App::Adapters::ProjectionStore::EncryptingProjectionStore.new(
        store: store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store
      )
    end

    # The checkpoint store, behind the encrypting decorator so the account
    # state a checkpoint caches is encrypted at the store boundary.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @return [Stweak::Ports::CheckpointStore]
    sig { params(key_store: Stweak::Ports::KeyStore).returns(Stweak::Ports::CheckpointStore) }
    def self.build_checkpoint_store(key_store)
      App::Adapters::CheckpointStore::EncryptingCheckpointStore.new(
        store: raw_checkpoint_store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store
      )
    end

    # The undecorated event store named by EVENT_STORE.
    #
    # @return [Stweak::Ports::EventStore]
    sig { returns(Stweak::Ports::EventStore) }
    def self.raw_event_store
      selection = ENV.fetch('EVENT_STORE', 'dynamodb')
      case selection
      when 'dynamodb' then App::Adapters::DynamoDBEventStore.new(client: dynamo, streams_table: streams_table)
      when 'memory' then Stweak::Adapters::EventStore::InMemoryEventStore.new
      else raise UnknownAdapter, "unknown EVENT_STORE #{selection}"
      end
    end

    # The undecorated projection store named by PROJECTION_STORE.
    #
    # @return [Stweak::Ports::ProjectionStore]
    sig { returns(Stweak::Ports::ProjectionStore) }
    def self.raw_projection_store
      selection = ENV.fetch('PROJECTION_STORE', 'sqlite')
      case selection
      when 'sqlite' then App::Adapters::SqliteProjectionStore.new(db: SQLite3::Database.new(database_path))
      when 'memory' then Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new
      else raise UnknownAdapter, "unknown PROJECTION_STORE #{selection}"
      end
    end

    # The undecorated checkpoint store named by CHECKPOINT_STORE.
    #
    # @return [Stweak::Ports::CheckpointStore]
    sig { returns(Stweak::Ports::CheckpointStore) }
    def self.raw_checkpoint_store
      selection = ENV.fetch('CHECKPOINT_STORE', 'redis')
      case selection
      when 'redis' then App::Adapters::RedisCheckpointStore.new(redis: redis)
      when 'memory' then Stweak::Adapters::CheckpointStore::InMemoryCheckpointStore.new
      else raise UnknownAdapter, "unknown CHECKPOINT_STORE #{selection}"
      end
    end

    # The SQLite file for the projection store, from STWEAK_DB.
    #
    # @return [String]
    sig { returns(String) }
    def self.database_path = ENV.fetch('STWEAK_DB', 'stweak.db')

    # The DynamoDB streams table, from STWEAK_STREAMS_TABLE.
    #
    # @return [String]
    sig { returns(String) }
    def self.streams_table = ENV.fetch('STWEAK_STREAMS_TABLE', 'stweak_streams')

    # The ElasticMQ queue, from STWEAK_QUEUE.
    #
    # @return [String]
    sig { returns(String) }
    def self.queue_name = ENV.fetch('STWEAK_QUEUE', 'stweak-events')

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
  # rubocop:enable Metrics/ClassLength
end
