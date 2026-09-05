# typed: false
# frozen_string_literal: true

# The lifecycle generator's spec drives real worker threads to prove stop
# releases them, and its example-group helpers are plain defs because the file
# is typed: false. The ThreadSafety and RSpec cops flag exactly what this spec
# is for, so the deliberate ones are disabled here rather than silenced one
# offense at a time.
# rubocop:disable Metrics/MethodLength
# rubocop:disable RSpec/ExampleLength
# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable Sorbet/BlockMethodDefinition
# rubocop:disable ThreadSafety/NewThread

require_relative 'spec_helper'
require_relative '../lib/lifecycle_generator'
require_relative '../lib/wiring'

RSpec.describe DataGenerator::LifecycleGenerator do
  # The lifecycle generator drives the same write side as the bounded
  # Generator, but continuously, so a spec needs control over its pacing. This
  # assembles it over the wiring's own adapter builders — the same choices the
  # real wiring makes — with a zero-length gap so a cycle never waits between
  # actions, and a web-admin URL on a port nothing listens on.
  def build_lifecycle_generator(gap: (0..0), web_admin_url: 'http://127.0.0.1:9/')
    wiring = DataGenerator::Wiring
    key_store = wiring.build_key_store
    subscription = wiring.build_subscription
    event_store = wiring.build_event_store(key_store, subscription)
    raw_projection = wiring.raw_projection_store
    projection_store = wiring.build_projection_store(key_store, raw_projection)
    wiring.register_projection(event_store, projection_store, subscription)
    checkpoint_store = wiring.build_checkpoint_store(key_store)
    handler = wiring.build_handler(event_store, raw_projection, key_store)
    disable_handler = Stweak::Domain::Accounts::DisableAccountHandler.new(
      event_store: event_store, checkpoint_store: checkpoint_store
    )
    delete_handler = Stweak::Domain::Accounts::DeleteAccountHandler.new(
      event_store: event_store, checkpoint_store: checkpoint_store
    )
    generator = DataGenerator::LifecycleGenerator.new(
      create_handler: handler, disable_handler: disable_handler, delete_handler: delete_handler,
      gap: gap, web_admin_url: web_admin_url
    )
    [generator, event_store, projection_store]
  end

  def events_from(event_store)
    events = []
    event_store.each_stream do |_owner_type, _stream_id, stream_events|
      events.concat(stream_events)
    end
    events
  end

  around do |example|
    saved = ENV.to_hash
    example.run
  ensure
    ENV.replace(saved)
  end

  describe 'the in-memory adapters' do
    before do
      ENV['EVENT_STORE'] = 'memory'
      ENV['PROJECTION_STORE'] = 'memory'
      ENV['KEY_STORE'] = 'memory'
      ENV['SUBSCRIPTION'] = 'memory'
      ENV['CHECKPOINT_STORE'] = 'memory'
    end

    describe 'a single lifecycle' do
      it 'creates, disables, then deletes one account' do
        generator, = build_lifecycle_generator
        account = generator.run_cycle

        expect(account.deleted).to be(true)
      end

      it 'writes the three lifecycle events in order' do
        generator, event_store, = build_lifecycle_generator
        generator.run_cycle

        expect(events_from(event_store).map(&:type))
          .to eq(%w[AccountCreated AccountDisabled AccountDeleted])
      end

      it 'restores the projection to its prior state once the account is deleted' do
        generator, _event_store, projection_store = build_lifecycle_generator
        expect { generator.run_cycle }
          .not_to(change { projection_store.read_all(table: :accounts).length })
      end
    end

    describe 'stopping' do
      it 'runs workers until stopped and answers promptly' do
        generator, = build_lifecycle_generator
        thread = Thread.new { generator.run(thread_count: 1) }
        sleep 0.2
        expect(generator.stop).to be(true)
        thread.join(2)
        expect(thread).not_to be_alive
      end

      it 'reports that a second stop is a no-op' do
        generator, = build_lifecycle_generator
        expect(generator.stop).to be(true)
        expect(generator.stop).to be(false)
      end
    end

    describe 'the web-admin checker' do
      it 'tolerates an unreachable web admin' do
        generator, = build_lifecycle_generator
        expect(generator.send(:check_web_admin)).to be_nil
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength
# rubocop:enable RSpec/ExampleLength
# rubocop:enable RSpec/MultipleExpectations
# rubocop:enable Sorbet/BlockMethodDefinition
# rubocop:enable ThreadSafety/NewThread
