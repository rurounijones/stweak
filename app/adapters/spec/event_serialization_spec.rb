# typed: false
# frozen_string_literal: true

require 'json'
require_relative 'spec_helper'
require_relative '../event_serialization'

# A test-only event whose schema has changed between versions, so deserialize
# has a real upcast to apply. The stored version-1 shape held `full_name`; the
# current shape holds `name`. No real domain event has a second version — the
# upcast machinery is production, the contrived migration is not.
class TypeChangedEvent < Stweak::Domain::Event
  CURRENT_VERSION = 2
  TYPE = 'TypeChangedEvent'

  attr_reader :name

  def initialize(name:, stream_id:, sequence:, occurred_at:, created_at: occurred_at)
    super(stream_id: stream_id, sequence: sequence, occurred_at: occurred_at, created_at: created_at)
    @name = name
  end

  def type
    TYPE
  end

  def version
    CURRENT_VERSION
  end

  def self.upcast(hash)
    return hash if hash.fetch('version') >= CURRENT_VERSION

    hash.merge('name' => hash.fetch('full_name'), 'version' => CURRENT_VERSION)
        .tap { |migrated| migrated.delete('full_name') }
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

RSpec.describe App::Adapters::EventSerialization do
  subject(:serializer) { Class.new { include App::Adapters::EventSerialization }.new }

  let(:v1_json) do
    JSON.generate(
      'type' => 'TypeChangedEvent', 'version' => 1,
      'stream_id' => '00000000-0000-4000-8000-000000000001',
      'sequence' => 1,
      'occurred_at' => '2026-01-02T03:04:05Z', 'created_at' => '2026-01-02T03:04:05Z',
      'full_name' => 'alice'
    )
  end

  before do
    stub_const('App::Adapters::EventSerialization::EVENT_CLASSES', { 'TypeChangedEvent' => TypeChangedEvent })
  end

  it 'upcasts an older-version event before rebuilding it' do
    expect(serializer.deserialize(v1_json)).to have_attributes(name: 'alice', version: 2)
  end

  it 'does not mutate the data it is given' do
    original = v1_json.dup
    serializer.deserialize(v1_json)
    expect(v1_json).to eq(original)
  end
end
