# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/event'
require_relative '../../lib/stweak/domain/id'

# A test-only event whose schema has changed, so upcasting has something real to
# do. The current shape (version 2) holds a `name`; the old shape (version 1)
# held a `full_name`. An instance can be built in either version, so a spec can
# serialize an old form the way old code would have written it, then read it
# back through the upcast and prove it arrives in the current shape without the
# stored form ever being rewritten.
#
# No real domain event has a second version, deliberately: the upcast machinery
# lives in production but is exercised by this double, so a contrived migration
# never enters the domain. See "Event versioning" in the design decisions.
class VersionedEvent < Stweak::Domain::Event
  CURRENT_VERSION = 2
  TYPE = 'VersionedEvent'

  attr_reader :name

  # rubocop:disable Metrics/ParameterLists -- an event constructor carries every field it records
  def initialize(name:, stream_id:, sequence:, occurred_at:, created_at: occurred_at, version: CURRENT_VERSION)
    super(stream_id: stream_id, sequence: sequence, occurred_at: occurred_at, created_at: created_at)
    @name = name
    @schema_version = version
  end
  # rubocop:enable Metrics/ParameterLists

  def type
    TYPE
  end

  # The version this instance serializes as, so a v1 instance writes the old
  # shape and a v2 instance the current one.
  def version
    @schema_version
  end

  def to_h
    base = super
    return base.merge('name' => name) unless @schema_version == 1

    base.merge('full_name' => name).tap { |hash| hash.delete('name') }
  end

  # Promote a stored v1 hash to the current shape: `full_name` becomes `name`
  # and the version is bumped. A hash already at the current version is returned
  # unchanged. The argument is never mutated.
  def self.upcast(hash)
    return hash if hash.fetch('version') >= CURRENT_VERSION

    hash.merge('name' => hash.fetch('full_name'), 'version' => CURRENT_VERSION)
        .tap { |migrated| migrated.delete('full_name') }
  end

  # from_h only ever sees the current shape, because upcast runs first.
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
