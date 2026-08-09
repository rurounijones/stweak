# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/aggregate'
require_relative '../../lib/stweak/domain/id'
require_relative '../../lib/stweak/ports/event_store'
require_relative '../../lib/stweak/ports/event_store_listener'
require_relative '../../lib/stweak/ports/event_subscription'
require_relative '../../lib/stweak/ports/key_store'

# A valid id the examples pass through the ports.
TEST_ID = Stweak::Domain::Id.new(value: '00000000-0000-4000-8000-0000000000aa')

# Minimal implementors of the two ports, exercising the contracts directly
# rather than only through the domain and adapters that use them.
class RecordingEventStore
  include Stweak::Ports::EventStore

  extend T::Sig

  attr_reader :appended, :read

  sig do
    override
      .params(
        owner_type: T.class_of(Stweak::Domain::Aggregate),
        stream_id: Stweak::Domain::Id,
        expected_version: Integer,
        events: T::Array[Stweak::Domain::Event]
      )
      .void
  end
  def append(owner_type:, stream_id:, expected_version:, events:)
    @appended = [owner_type, stream_id, expected_version, events]
  end

  sig do
    override
      .params(
        owner_type: T.class_of(Stweak::Domain::Aggregate),
        stream_id: Stweak::Domain::Id,
        after: Integer
      )
      .returns(T::Array[Stweak::Domain::Event])
  end
  def read_stream(owner_type:, stream_id:, after: 0)
    @read = [owner_type, stream_id, after]
    []
  end

  # rubocop:disable Naming/BlockForwarding -- srb tc does not recognise
  # anonymous `&`; the named block parameter is required to match the sig.
  sig do
    override
      .params(blk: T.proc.params(owner_type: T.class_of(Stweak::Domain::Aggregate),
                                 stream_id: Stweak::Domain::Id,
                                 events: T::Array[Stweak::Domain::Event]).void)
      .void
  end
  def each_stream(&blk); end
  # rubocop:enable Naming/BlockForwarding
end

# A minimal listener, for exercising the listener port and the subscription.
class RecordingListener
  include Stweak::Ports::EventStoreListener

  extend T::Sig

  attr_reader :deliveries

  sig { void }
  def initialize
    @deliveries = T.let([], T::Array[T::Array[Stweak::Domain::Event]])
  end

  sig { override.params(events: T::Array[Stweak::Domain::Event]).void }
  def on_events_appended(events:)
    @deliveries << events
  end
end

class HashSubscription
  include Stweak::Ports::EventSubscription

  extend T::Sig

  def initialize
    @listeners = []
  end

  sig { override.params(listener: Stweak::Ports::EventStoreListener).void }
  def register(listener:)
    @listeners << listener
  end

  sig { override.params(events: T::Array[Stweak::Domain::Event]).void }
  def publish(events:)
    @listeners.each { |listener| listener.on_events_appended(events: events) }
  end
end

class HashKeyStore
  include Stweak::Ports::KeyStore

  extend T::Sig

  def initialize
    @keys = {}
  end

  sig do
    override
      .params(
        owner_type: T.class_of(Stweak::Domain::Aggregate),
        owner_id: Stweak::Domain::Id
      )
      .returns(T.nilable(String))
  end
  def get(owner_type:, owner_id:)
    @keys[[owner_type, owner_id]]
  end

  sig do
    override
      .params(
        owner_type: T.class_of(Stweak::Domain::Aggregate),
        owner_id: Stweak::Domain::Id,
        key: String
      )
      .void
  end
  def put(owner_type:, owner_id:, key:)
    @keys[[owner_type, owner_id]] = key
  end

  sig do
    override
      .params(
        owner_type: T.class_of(Stweak::Domain::Aggregate),
        owner_id: Stweak::Domain::Id
      )
      .void
  end
  def delete(owner_type:, owner_id:)
    @keys.delete([owner_type, owner_id])
  end
end

RSpec.describe Stweak::Ports do
  describe Stweak::Ports::EventStore do
    it 'accepts an implementor that records an append' do
      store = RecordingEventStore.new
      store.append(owner_type: Stweak::Domain::Aggregate, stream_id: TEST_ID, expected_version: 0, events: [])
      expect(store.appended).to eq([Stweak::Domain::Aggregate, TEST_ID, 0, []])
    end

    it 'accepts an implementor that records a read, defaulting to the whole stream' do
      store = RecordingEventStore.new
      store.read_stream(owner_type: Stweak::Domain::Aggregate, stream_id: TEST_ID)
      expect(store.read).to eq([Stweak::Domain::Aggregate, TEST_ID, 0])
    end

    it 'accepts an implementor that records a read after a sequence' do
      store = RecordingEventStore.new
      store.read_stream(owner_type: Stweak::Domain::Aggregate, stream_id: TEST_ID, after: 5)
      expect(store.read).to eq([Stweak::Domain::Aggregate, TEST_ID, 5])
    end

    it 'accepts an implementor that yields each stream' do
      store = RecordingEventStore.new
      count = 0
      store.each_stream { |_owner, _id, _events| count += 1 }
      expect(count).to eq(0)
    end
  end

  describe Stweak::Ports::KeyStore do
    it 'accepts an implementor that stores and returns a key' do
      store = HashKeyStore.new
      store.put(owner_type: Stweak::Domain::Aggregate, owner_id: TEST_ID, key: 'secret')
      expect(store.get(owner_type: Stweak::Domain::Aggregate, owner_id: TEST_ID)).to eq('secret')
    end

    it 'accepts an implementor that deletes a key' do
      store = HashKeyStore.new
      store.put(owner_type: Stweak::Domain::Aggregate, owner_id: TEST_ID, key: 'secret')
      store.delete(owner_type: Stweak::Domain::Aggregate, owner_id: TEST_ID)
      expect(store.get(owner_type: Stweak::Domain::Aggregate, owner_id: TEST_ID)).to be_nil
    end
  end

  describe Stweak::Ports::EventSubscription do
    it 'accepts an implementor that registers a listener' do
      subscription = HashSubscription.new
      listener = RecordingListener.new
      subscription.register(listener: listener)
      subscription.publish(events: [])
      expect(listener.deliveries).to eq([[]])
    end

    it 'accepts an implementor that delivers to every listener' do
      subscription = HashSubscription.new
      listeners = Array.new(2) { RecordingListener.new }
      listeners.each { |listener| subscription.register(listener: listener) }
      subscription.publish(events: [])
      expect(listeners.map(&:deliveries)).to all(eq([[]]))
    end
  end
end
