# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/aggregate'

AGGREGATE_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-000000000001')

# A concrete event standing in for the abstract Event base, so aggregates can
# be exercised with real events rather than mocks.
class SequenceEvent < Stweak::Domain::Event
  VERSION = 1

  def version
    VERSION
  end

  def self.from_h(hash)
    new(
      stream_id: Stweak::Domain::Id.new(value: hash.fetch('stream_id')),
      sequence: hash.fetch('sequence'),
      occurred_at: Time.iso8601(hash.fetch('occurred_at'))
    )
  end
end

# A concrete aggregate standing in for the abstract Aggregate base, so the
# shared behaviour can be exercised directly.
class SampleAggregate < Stweak::Domain::Aggregate
  attr_reader :applied_events

  def initialize(id:, applied_events: [])
    super(id: id)
    @applied_events = applied_events
  end

  def apply(event)
    @applied_events << event
  end

  def add(event)
    record(event)
  end
end

# Builds a minimal event at the given position in the stream.
def build_event(sequence)
  SequenceEvent.new(
    stream_id: AGGREGATE_ID,
    sequence: sequence,
    occurred_at: Time.utc(2026, 1, 2, 3, 4, 5)
  )
end

RSpec.describe Stweak::Domain::Aggregate do
  subject(:aggregate) { SampleAggregate.new(id: AGGREGATE_ID) }

  it 'exposes its id' do
    expect(aggregate.id).to eq(AGGREGATE_ID)
  end

  it 'starts at version zero' do
    expect(aggregate.expected_version).to eq(0)
  end

  it 'starts with no uncommitted events' do
    expect(aggregate.uncommitted_events).to eq([])
  end

  it 'replays a stream, applying each event in order' do
    rebuilt = SampleAggregate.replay(id: AGGREGATE_ID, events: [build_event(1), build_event(2)])
    expect(rebuilt.applied_events).to eq([build_event(1), build_event(2)])
  end

  it 'tracks the expected version to the last replayed event' do
    rebuilt = SampleAggregate.replay(id: AGGREGATE_ID, events: [build_event(2)])
    expect(rebuilt.expected_version).to eq(2)
  end

  it 'replays an empty stream at version zero' do
    rebuilt = SampleAggregate.replay(id: AGGREGATE_ID, events: [])
    expect(rebuilt.expected_version).to eq(0)
  end

  it 'stages a recorded event' do
    aggregate.add(build_event(1))
    expect(aggregate.uncommitted_events).to eq([build_event(1)])
  end

  it 'applies a recorded event' do
    aggregate.add(build_event(1))
    expect(aggregate.applied_events).to eq([build_event(1)])
  end
end
