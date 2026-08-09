# typed: false
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require_relative 'spec_helper'
require_relative '../lib/data_generator'
require_relative '../lib/wiring'

RSpec.describe DataGenerator::Generator do
  subject(:generator) { DataGenerator::Wiring.build }

  around do |example|
    saved = ENV.to_hash
    example.run
  ensure
    ENV.replace(saved)
  end

  describe 'the in-memory adapters' do
    before do
      ENV['EVENT_STORE'] = 'memory'
      ENV['PROJECTION_STORE'] = 'memory'
      ENV['KEY_STORE'] = 'memory'
      ENV['SUBSCRIPTION'] = 'memory'
      ENV['CHECKPOINT_STORE'] = 'memory'
    end

    it 'creates the requested number of accounts' do
      expect(generator.run(2).length).to eq(2)
    end

    it 'writes an event for every created account' do
      generator.run(2)
      expect(generator.events.length).to eq(2)
    end

    it 'writes AccountCreated events' do
      generator.run(1)
      expect(generator.events.first).to be_a(Stweak::Domain::Accounts::AccountCreated)
    end
  end

  describe 'an unknown selector' do
    let(:wiring) { DataGenerator::Wiring }
    let(:unknown) { DataGenerator::Wiring::UnknownAdapter }

    it 'rejects an unknown event store' do
      ENV['EVENT_STORE'] = 'bogus'
      expect { wiring.raw_event_store }.to raise_error(unknown, /bogus/)
    end

    it 'rejects an unknown projection store' do
      ENV['PROJECTION_STORE'] = 'bogus'
      expect { wiring.raw_projection_store }.to raise_error(unknown, /bogus/)
    end

    it 'rejects an unknown checkpoint store' do
      ENV['CHECKPOINT_STORE'] = 'bogus'
      expect { wiring.raw_checkpoint_store }.to raise_error(unknown, /bogus/)
    end

    it 'rejects an unknown key store' do
      ENV['KEY_STORE'] = 'bogus'
      expect { wiring.build_key_store }.to raise_error(unknown, /bogus/)
    end

    it 'rejects an unknown subscription' do
      ENV['SUBSCRIPTION'] = 'bogus'
      expect { wiring.build_subscription }.to raise_error(unknown, /bogus/)
    end
  end

  # The real adapters need the devcontainer services (DynamoDB Local, ElasticMQ,
  # Redis); SQLite runs in memory. A unique table and queue per run keep
  # concurrent runs from colliding.
  describe 'the real adapters', :integration do
    let(:streams_table) { "stweak_streams_#{object_id}" }
    let(:queue_name) { "stweak-events-#{object_id}" }

    before do
      ENV['EVENT_STORE'] = 'dynamodb'
      ENV['PROJECTION_STORE'] = 'sqlite'
      ENV['KEY_STORE'] = 'redis'
      ENV['SUBSCRIPTION'] = 'elasticmq'
      ENV['CHECKPOINT_STORE'] = 'redis'
      ENV['STWEAK_DB'] = ':memory:'
      ENV['STWEAK_STREAMS_TABLE'] = streams_table
      ENV['STWEAK_QUEUE'] = queue_name
      DataGenerator::Wiring.redis.flushdb
    end

    after do
      DataGenerator::Wiring.dynamo.delete_table(table_name: streams_table)
    rescue Aws::DynamoDB::Errors::ResourceNotFoundException
      nil
    end

    it 'creates accounts through the real adapters' do
      expect(generator.run(2).length).to eq(2)
    end
  end
end
