# typed: false
# frozen_string_literal: true

require 'redis'
require_relative '../spec_helper'
require_relative '../../checkpoint_store/redis'
require_relative '../../../../spec/support/checkpoint_store_examples'

RSpec.describe App::Adapters::RedisCheckpointStore do
  subject(:store) { described_class.new(redis: redis) }

  # The Redis service is a sibling container in the dev container (REDIS_URL),
  # localhost in CI.
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379')) }

  before { redis.flushdb }

  it_behaves_like 'a checkpoint store'
end
