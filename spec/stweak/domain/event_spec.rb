# typed: false
# frozen_string_literal: true

require 'prop_check'
require_relative '../../../lib/stweak/domain/event'
require_relative '../../support/property/generators'
require_relative '../../support/versioned_event'

# A concrete event standing in for the abstract Event base, so the shared
# behaviour can be exercised directly.
class SampleEvent < Stweak::Domain::Event
  VERSION = 1
  TYPE = 'SampleEvent'

  def type
    TYPE
  end

  def version
    VERSION
  end

  def self.pii_fields
    [:name]
  end

  attr_reader :name

  def initialize(name:, stream_id:, sequence:, occurred_at:, created_at: occurred_at)
    super(stream_id: stream_id, sequence: sequence, occurred_at: occurred_at, created_at: created_at)
    @name = name
  end

  def to_h
    super.merge('name' => name)
  end

  def self.from_h(hash)
    new(
      name: hash.fetch('name'),
      stream_id: Stweak::Domain::Id.new(value: hash.fetch('stream_id')),
      sequence: hash.fetch('sequence'),
      occurred_at: Time.iso8601(hash.fetch('occurred_at')),
      created_at: Time.iso8601(hash.fetch('created_at'))
    )
  end
end

# An event that adds no constructor of its own, so it exercises the base Event
# initializer directly — in particular its default of created_at to occurred_at,
# which a subclass with its own constructor would mask.
class BaselineEvent < Stweak::Domain::Event
  VERSION = 1
  TYPE = 'BaselineEvent'

  def type
    TYPE
  end

  def version
    VERSION
  end
end

# Builds a SampleEvent from generated values, wrapping the stream id.
def build_sample_event(stream_id, sequence, occurred_at, created_at, name)
  SampleEvent.new(
    name: name,
    stream_id: Stweak::Domain::Id.new(value: stream_id),
    sequence: sequence,
    occurred_at: occurred_at,
    created_at: created_at
  )
end

# Builds a VersionedEvent in a chosen schema version, so a spec can serialize an
# old shape and read it back through the upcast.
def build_versioned_event(stream_id, occurred_at, version)
  VersionedEvent.new(name: 'alice', stream_id: stream_id, sequence: 1, occurred_at: occurred_at, version: version)
end

RSpec.describe Stweak::Domain::Event do
  include PropertyGenerators

  subject(:event) do
    SampleEvent.new(name: 'alice', stream_id: stream_id, sequence: 1, occurred_at: occurred_at)
  end

  let(:stream_id) { Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:occurred_at) { Time.utc(2026, 1, 2, 3, 4, 5) }

  it 'exposes the stream it belongs to' do
    expect(event.stream_id).to eq(stream_id)
  end

  it 'exposes its position in the stream' do
    expect(event.sequence).to eq(1)
  end

  it 'exposes when it happened' do
    expect(event.occurred_at).to eq(occurred_at)
  end

  it 'exposes when it was committed' do
    created_at = Time.utc(2026, 2, 3, 4, 5, 6)
    committed = event.with('created_at' => created_at.iso8601)
    expect(committed.created_at).to eq(created_at)
  end

  it 'defaults created_at to occurred_at' do
    expect(event.created_at).to eq(occurred_at)
  end

  it 'defaults created_at to occurred_at at the base' do
    baseline = BaselineEvent.new(stream_id: stream_id, sequence: 1, occurred_at: occurred_at)
    expect(baseline.created_at).to eq(occurred_at)
  end

  it 'declares its type' do
    expect(event.type).to eq('SampleEvent')
  end

  it 'reports its schema version' do
    expect(event.version).to eq(1)
  end

  it 'defaults to no PII fields on the base event' do
    expect(described_class.pii_fields).to eq([])
  end

  it 'defaults to not shredding the owner key on the base event' do
    expect(described_class.shreds_owner_key?).to be(false)
  end

  it 'declares its PII fields' do
    expect(SampleEvent.pii_fields).to eq([:name])
  end

  it 'rejects a non-positive sequence' do
    expect { SampleEvent.new(name: 'alice', stream_id: stream_id, sequence: 0, occurred_at: occurred_at) }
      .to raise_error(Stweak::Domain::ValidationError, /sequence/)
  end

  it 'serializes its metadata and its own fields' do
    expect(event.to_h).to eq(
      'type' => 'SampleEvent', 'version' => 1, 'stream_id' => stream_id.to_s,
      'sequence' => 1, 'occurred_at' => occurred_at.iso8601,
      'created_at' => occurred_at.iso8601, 'name' => 'alice'
    )
  end

  it 'rebuilds itself from its serialized form' do
    expect(SampleEvent.from_h(event.to_h)).to eq(event)
  end

  it 'returns a copy with an attribute replaced' do
    expect(event.with('sequence' => 2).sequence).to eq(2)
  end

  it 'leaves the original untouched when copied' do
    event.with('sequence' => 2)
    expect(event.sequence).to eq(1)
  end

  it 'is equal to an event with the same serialized form' do
    expect(SampleEvent.from_h(event.to_h) == event).to be(true)
  end

  it 'is not equal to an event with different fields' do
    other = SampleEvent.new(name: 'bob', stream_id: stream_id, sequence: 1, occurred_at: occurred_at)
    expect(event == other).to be(false)
  end

  it 'is not equal to a non-event' do
    expect(event == Object.new).to be(false)
  end

  it 'is eql to an event with the same serialized form' do
    expect(SampleEvent.from_h(event.to_h).eql?(event)).to be(true)
  end

  it 'hashes to the hash of its serialized form' do
    expect(event.hash).to eq(event.to_h.hash)
  end

  it 'round-trips any event through its serialized form', :property do
    PropCheck.forall(uuid, positive_integer, time, time, string) do |stream_id, sequence, occurred_at, created_at, name|
      event = build_sample_event(stream_id, sequence, occurred_at, created_at, name)
      expect(SampleEvent.from_h(event.to_h)).to eq(event)
    end
  end

  describe '.upcast' do
    it 'leaves an event with no schema change untouched' do
      expect(SampleEvent.upcast(event.to_h)).to eq(event.to_h)
    end

    it 'translates an older shape to the current one' do
      upcast = VersionedEvent.upcast(build_versioned_event(stream_id, occurred_at, 1).to_h)
      expect(upcast).to eq(build_versioned_event(stream_id, occurred_at, 2).to_h)
    end

    it 'rebuilds the current event from an upcast older shape' do
      upcast = VersionedEvent.upcast(build_versioned_event(stream_id, occurred_at, 1).to_h)
      expect(VersionedEvent.from_h(upcast)).to have_attributes(name: 'alice', version: 2)
    end

    it 'does not mutate the hash it is given' do
      stored = build_versioned_event(stream_id, occurred_at, 1).to_h
      expect { VersionedEvent.upcast(stored) }.not_to(change { stored.dup })
    end

    it 'is identity on an already-current shape', :property do
      PropCheck.forall(uuid, positive_integer, time, time, string) do |id, seq, occurred, created, name|
        serialized = build_sample_event(id, seq, occurred, created, name).to_h
        expect(SampleEvent.upcast(serialized)).to eq(serialized)
      end
    end
  end
end
