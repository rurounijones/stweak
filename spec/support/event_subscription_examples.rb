# typed: false
# frozen_string_literal: true

require_relative '../../lib/stweak/domain/event'
require_relative '../../lib/stweak/ports/event_store_listener'

# A minimal listener that records every delivery.
class SubscribedListener
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

# The contract every event subscription must honour. Any future durable
# implementation — an SQS-backed transport, say — is held to this before it is
# trusted with real events.
RSpec.shared_examples 'an event subscription' do
  it 'delivers a published batch to a registered listener' do
    listener = SubscribedListener.new
    subject.register(listener: listener)
    subject.publish(events: [])
    expect(listener.deliveries).to eq([[]])
  end

  it 'delivers to every registered listener' do
    listeners = Array.new(2) { SubscribedListener.new }
    listeners.each { |listener| subject.register(listener: listener) }
    subject.publish(events: [])
    expect(listeners.map(&:deliveries)).to all(eq([[]]))
  end

  it 'does not deliver to a listener that has not registered' do
    listener = SubscribedListener.new
    subject.publish(events: [])
    expect(listener.deliveries).to eq([])
  end
end
