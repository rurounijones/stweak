# typed: false
# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'redis'
require_relative 'spec_helper'
require_relative '../lib/data_generator'
require_relative '../lib/wiring'

class RecordingRedis < Redis
  attr_reader :commands

  def initialize(**kwargs)
    super
    @commands = []
  end

  def get(*args, **kwargs)
    @commands << :get
    super
  end

  def set(*args, **kwargs)
    @commands << :set
    super
  end
end

RSpec.describe DataGenerator::Generator do
  subject(:generator) { built.generator }

  let(:redis) { RecordingRedis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379')) }
  let(:built) do
    DataGenerator::Wiring.build(
      database_path: ':memory:',
      streams_table: "stweak_streams_#{object_id}",
      queue_name: "stweak-events-#{object_id}"
    )
  end
  let(:dynamo) { DataGenerator::Wiring.dynamo }

  before do
    allow(DataGenerator::Wiring).to receive(:redis).and_return(redis)
    redis.flushdb
  end

  after do
    built.subscription.stop
    dynamo.delete_table(table_name: "stweak_streams_#{object_id}")
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    nil
  end

  it 'uses only the account key reads while creating one account' do
    generator.run(1)
    built.subscription.drain

    expect(redis.commands).to eq(%i[get get set get])
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
