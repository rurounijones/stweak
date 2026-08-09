# typed: false
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require_relative 'spec_helper'
require_relative '../lib/data_generator'
require_relative '../lib/wiring'

RSpec.describe DataGenerator::Generator do
  subject(:generator) do
    DataGenerator::Wiring.build(
      database_path: ':memory:',
      streams_table: "stweak_streams_#{object_id}",
      queue_name: "stweak-events-#{object_id}"
    )
  end

  let(:dynamo) { DataGenerator::Wiring.dynamo }
  let(:redis) { DataGenerator::Wiring.redis }

  before { redis.flushdb }

  after do
    dynamo.delete_table(table_name: "stweak_streams_#{object_id}")
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    nil
  end

  it 'creates accounts through the real adapters' do
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
