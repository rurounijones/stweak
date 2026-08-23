# typed: false
# frozen_string_literal: true

require_relative '../adapters/checkpoint_store/redis'
require_relative '../adapters/event_store/dynamo_db'
require_relative '../adapters/event_subscription/elastic_mq'
require_relative '../adapters/key_store/redis'
require_relative 'adapters/event_store_tracing'
require_relative 'adapters/event_subscription_tracing'
require_relative 'adapters/port_tracing'
require_relative 'adapters/redis_checkpoint_store_tracing'
require_relative 'adapters/redis_key_store_tracing'
require_relative '../adapters/checkpoint_store/encrypting'
require_relative '../adapters/projection_store/encrypting'
require_relative '../adapters/projection/usernames'
require_relative '../adapters/security/bcrypt_password_hasher'
require_relative '../adapters/projection_store/sqlite'
require_relative '../../lib/stweak/adapters/checkpoint_store/in_memory'
require_relative '../../lib/stweak/adapters/event_store/in_memory'
require_relative '../../lib/stweak/adapters/event_subscription/in_memory'
require_relative '../../lib/stweak/adapters/key_store/in_memory'
require_relative '../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../lib/stweak/adapters/security/pbkdf2_password_hasher'
require_relative '../../lib/stweak/adapters/event_store/encrypting'
require_relative '../../lib/stweak/domain/security/password_hasher'

module App
  module Observability
    # Installs OpenTelemetry wrappers onto the app-area adapters, giving their
    # AWS SDK client spans a semantically-named parent, without adding
    # telemetry to the adapter classes themselves.
    module Adapters
      class << self
        # Install all adapter wrappers once. Calling this repeatedly is
        # harmless.
        #
        # @return [void]
        def install
          wrappers.each { |target, wrapper| prepend_once(target, wrapper) }
        end

        private

        # rubocop:disable Metrics/MethodLength -- a flat registry of
        # adapter-to-wrapper pairs; splitting it would obscure the table.
        def wrappers
          [
            [App::Adapters::DynamoDBEventStore, EventStoreTracing],
            [App::Adapters::ElasticMqSubscription, EventSubscriptionTracing],
            [App::Adapters::RedisCheckpointStore, RedisCheckpointStoreTracing],
            [App::Adapters::RedisKeyStore, RedisKeyStoreTracing],
            [App::Adapters::BcryptPasswordHasher, PortTracing],
            [Stweak::Adapters::Security::Pbkdf2PasswordHasher, PortTracing],
            [App::Adapters::Projection::Usernames, PortTracing],
            [App::Adapters::SqliteProjectionStore, ProjectionStoreTracing],
            [Stweak::Adapters::ProjectionStore::InMemoryProjectionStore, ProjectionStoreTracing],
            [App::Adapters::CheckpointStore::EncryptingCheckpointStore, EncryptingCheckpointStoreTracing],
            [App::Adapters::ProjectionStore::EncryptingProjectionStore, EncryptingProjectionStoreTracing],
            [Stweak::Adapters::EventStore::EncryptingEventStore, EncryptingEventStoreTracing],
            [Stweak::Adapters::EventStore::InMemoryEventStore, EventStoreTracing],
            [Stweak::Adapters::EventSubscription::InMemoryEventSubscription, EventSubscriptionTracing],
            [Stweak::Adapters::CheckpointStore::InMemoryCheckpointStore, RedisCheckpointStoreTracing],
            [Stweak::Adapters::KeyStore::InMemoryKeyStore, RedisKeyStoreTracing]
          ]
        end
        # rubocop:enable Metrics/MethodLength

        # @param target [Module]
        # @param wrapper [Module]
        # @return [void]
        def prepend_once(target, wrapper)
          target.prepend(wrapper) unless target.ancestors.include?(wrapper)
        end
      end
    end
  end
end
