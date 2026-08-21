# typed: false
# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/wiring'

RSpec.describe WebAdmin::Wiring do
  around do |example|
    saved = ENV.to_hash
    example.run
  ensure
    ENV.replace(saved)
  end

  describe 'the memory adapters' do
    before do
      ENV['EVENT_STORE'] = 'memory'
      ENV['PROJECTION_STORE'] = 'memory'
      ENV['KEY_STORE'] = 'memory'
    end

    it 'builds a reader over empty in-memory stores' do
      reader = described_class.reader

      aggregate_failures do
        expect(reader).to be_a(WebAdmin::Reader)
        expect(reader.accounts).to eq([])
      end
    end
  end

  describe 'an unknown selector' do
    it 'rejects an unknown event store' do
      ENV['EVENT_STORE'] = 'bogus'
      expect { described_class.raw_event_store }.to raise_error(described_class::UnknownAdapter, /bogus/)
    end

    it 'rejects an unknown projection store' do
      ENV['PROJECTION_STORE'] = 'bogus'
      expect { described_class.raw_projection_store }.to raise_error(described_class::UnknownAdapter, /bogus/)
    end

    it 'rejects an unknown key store' do
      ENV['KEY_STORE'] = 'bogus'
      expect { described_class.build_key_store }.to raise_error(described_class::UnknownAdapter, /bogus/)
    end

    it 'rejects an unknown password hasher' do
      ENV['PASSWORD_HASHER'] = 'bogus'
      expect { described_class.build_password_hasher }.to raise_error(described_class::UnknownAdapter, /bogus/)
    end
  end

  describe 'the password hasher selector' do
    it 'builds pbkdf2 when selected' do
      ENV['PASSWORD_HASHER'] = 'pbkdf2'
      expect(described_class.build_password_hasher).to be_a(Stweak::Adapters::Security::Pbkdf2PasswordHasher)
    end
  end

  # The real adapters need the devcontainer services (DynamoDB Local, Redis);
  # SQLite runs in memory. This mirrors the data_generator's integration spec.
  describe 'the real adapters', :integration do
    let(:streams_table) { "web_admin_streams_#{object_id}" }

    before do
      ENV['EVENT_STORE'] = 'dynamodb'
      ENV['PROJECTION_STORE'] = 'sqlite'
      ENV['KEY_STORE'] = 'redis'
      ENV['STWEAK_DB'] = ':memory:'
      ENV['STWEAK_STREAMS_TABLE'] = streams_table
    end

    after do
      described_class.dynamo.delete_table(table_name: streams_table)
    rescue Aws::DynamoDB::Errors::ResourceNotFoundException
      # already gone
    end

    it 'builds a reader over the real stores' do
      reader = described_class.reader

      aggregate_failures do
        expect(reader).to be_a(WebAdmin::Reader)
        expect(reader.accounts).to eq([])
      end
    end
  end
end
