# typed: strict
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'redis'
require 'sqlite3'
require 'sorbet-runtime'
require 'stweak'
require_relative '../../../adapters/event_store/dynamo_db'
require_relative '../../../adapters/projection_store/sqlite'
require_relative '../../../adapters/projection_store/encrypting'
require_relative '../../../adapters/key_store/redis'
require_relative '../../../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../../../lib/stweak/adapters/encryption/aes_gcm'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative 'reader'

require_relative '../../../adapters/security/bcrypt_password_hasher'

module WebAdmin
  # The composition root: it reads the adapter selection from the environment
  # (populated from the shared drivers .env; see ../../.env.example) and
  # assembles a read-only Reader over the chosen stores. It honours the same
  # EVENT_STORE, PROJECTION_STORE and KEY_STORE selectors the data generator
  # does, so one .env drives both. dotenv populates ENV; this class still reads
  # ENV.fetch, so only the source of the vars is new, not the way they are
  # read. It never touches the write side — no subscription, no hasher, no
  # checkpoint store.
  class Wiring
    extend T::Sig

    # Raised when a selector names an adapter that does not exist.
    class UnknownAdapter < StandardError; end

    # Build the read facade over the selected adapters. The one key store is
    # shared by both encrypting decorators, so a single key decrypts a person's
    # data in the projection and the event log alike.
    #
    # @return [WebAdmin::Reader]
    sig { returns(WebAdmin::Reader) }
    def self.reader
      key_store = build_key_store
      WebAdmin::Reader.new(
        projection_store: build_projection_store(key_store),
        event_store: build_event_store(key_store),
        password_hasher: build_password_hasher
      )
    end

    # The password verifier used by the login page. The web admin defaults to
    # bcrypt, matching the data generator's stored hashes; PBKDF2 is available
    # for memory-only demonstrations.
    #
    # @return [Stweak::Domain::Security::PasswordHasher]
    sig { returns(Stweak::Domain::Security::PasswordHasher) }
    def self.build_password_hasher
      case ENV.fetch('PASSWORD_HASHER', 'bcrypt')
      when 'bcrypt' then ::App::Adapters::BcryptPasswordHasher.new
      when 'pbkdf2' then Stweak::Adapters::Security::Pbkdf2PasswordHasher.new
      else raise UnknownAdapter, "unknown PASSWORD_HASHER #{ENV.fetch('PASSWORD_HASHER')}"
      end
    end

    # The key store, from KEY_STORE.
    #
    # @return [Stweak::Ports::KeyStore]
    sig { returns(Stweak::Ports::KeyStore) }
    def self.build_key_store
      selection = ENV.fetch('KEY_STORE', 'redis')
      case selection
      when 'redis' then ::App::Adapters::RedisKeyStore.new(redis: redis)
      when 'memory' then Stweak::Adapters::KeyStore::InMemoryKeyStore.new
      else raise UnknownAdapter, "unknown KEY_STORE #{selection}"
      end
    end

    # The projection store, from PROJECTION_STORE, behind the encrypting
    # decorator so display names and emails come back decrypted.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @return [Stweak::Ports::ProjectionStore]
    sig { params(key_store: Stweak::Ports::KeyStore).returns(Stweak::Ports::ProjectionStore) }
    def self.build_projection_store(key_store)
      ::App::Adapters::ProjectionStore::EncryptingProjectionStore.new(
        store: raw_projection_store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store
      )
    end

    # The event store, from EVENT_STORE, behind the encrypting decorator; no
    # subscription, because a read-only app never appends.
    #
    # @param key_store [Stweak::Ports::KeyStore]
    # @return [Stweak::Ports::EventStore]
    sig { params(key_store: Stweak::Ports::KeyStore).returns(Stweak::Ports::EventStore) }
    def self.build_event_store(key_store)
      Stweak::Adapters::EventStore::EncryptingEventStore.new(
        store: raw_event_store,
        cipher: Stweak::Adapters::Encryption::AesGcm.new,
        key_store: key_store,
        subscription: nil
      )
    end

    # The undecorated projection store named by PROJECTION_STORE.
    #
    # @return [Stweak::Ports::ProjectionStore]
    sig { returns(Stweak::Ports::ProjectionStore) }
    def self.raw_projection_store
      selection = ENV.fetch('PROJECTION_STORE', 'sqlite')
      case selection
      when 'sqlite'
        ::App::Adapters::SqliteProjectionStore.new(db: SQLite3::Database.new(ENV.fetch('STWEAK_DB', 'stweak.db')))
      when 'memory'
        Stweak::Adapters::ProjectionStore::InMemoryProjectionStore.new
      else
        raise UnknownAdapter, "unknown PROJECTION_STORE #{selection}"
      end
    end

    # The undecorated event store named by EVENT_STORE.
    #
    # @return [Stweak::Ports::EventStore]
    sig { returns(Stweak::Ports::EventStore) }
    def self.raw_event_store
      selection = ENV.fetch('EVENT_STORE', 'dynamodb')
      table = ENV.fetch('STWEAK_STREAMS_TABLE', 'stweak_streams')
      case selection
      when 'dynamodb' then ::App::Adapters::DynamoDBEventStore.new(client: dynamo, streams_table: table)
      when 'memory' then Stweak::Adapters::EventStore::InMemoryEventStore.new
      else raise UnknownAdapter, "unknown EVENT_STORE #{selection}"
      end
    end

    # The DynamoDB client, from the environment (compose service name in the
    # dev container, localhost otherwise).
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

    # The Redis client, from the environment.
    #
    # @return [Redis]
    sig { returns(Redis) }
    def self.redis
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
    end
  end
end
