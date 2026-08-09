# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/checkpoint'

# A subclass, so equality is pinned to is_a? rather than instance_of?: a
# checkpoint subclass carries the same state and version, and compares equal.
class CheckpointSubclass < Stweak::Domain::Checkpoint
end

RSpec.describe Stweak::Domain::Checkpoint do
  let(:checkpoint) { described_class.new(state: { 'username' => 'alice' }, version: 100) }

  it 'exposes the serialized state' do
    expect(checkpoint.state).to eq('username' => 'alice')
  end

  it 'exposes the version' do
    expect(checkpoint.version).to eq(100)
  end

  it 'accepts version zero, the state of a stream with no events' do
    expect(described_class.new(state: {}, version: 0).version).to eq(0)
  end

  it 'rejects a negative version' do
    expect { described_class.new(state: {}, version: -1) }
      .to raise_error(Stweak::Domain::ValidationError, 'version must not be negative')
  end

  it 'is equal to a checkpoint with the same state and version' do
    other = described_class.new(state: { 'username' => 'alice' }, version: 100)
    expect(checkpoint).to eq(other)
  end

  it 'is not equal to a checkpoint at a different version' do
    other = described_class.new(state: { 'username' => 'alice' }, version: 200)
    expect(checkpoint).not_to eq(other)
  end

  it 'is not equal to a checkpoint with a different state' do
    other = described_class.new(state: { 'username' => 'bob' }, version: 100)
    expect(checkpoint).not_to eq(other)
  end

  it 'is not equal to a non-checkpoint' do
    expect(checkpoint).not_to eq(state: { 'username' => 'alice' }, version: 100)
  end

  it 'is equal to a checkpoint subclass with the same state and version' do
    subclass = CheckpointSubclass.new(state: { 'username' => 'alice' }, version: 100)
    expect(checkpoint).to eq(subclass)
  end

  it 'is eql? to a checkpoint with the same state and version' do
    other = described_class.new(state: { 'username' => 'alice' }, version: 100)
    expect(checkpoint.eql?(other)).to be(true)
  end

  it 'is not eql? to a checkpoint with a different version' do
    other = described_class.new(state: { 'username' => 'alice' }, version: 200)
    expect(checkpoint.eql?(other)).to be(false)
  end

  it 'hashes to the hash of its state and version' do
    expect(checkpoint.hash).to eq([checkpoint.state, checkpoint.version].hash)
  end
end
