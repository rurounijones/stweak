# typed: false
# frozen_string_literal: true

# These doubles deliberately share one file: they are private fixtures for the
# instrumentation contract, not production collaborators.
# rubocop:disable Style/Documentation
# rubocop:disable Lint/UnusedMethodArgument
# rubocop:disable RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/ExampleLength

require 'opentelemetry'
require_relative 'spec_helper'
require_relative '../../observability/domain'

module DomainObservabilityDoubles
  class RecordingTracer
    attr_reader :spans

    def initialize
      @spans = []
    end

    def in_span(name, attributes: {}, **)
      @spans << { name: name, attributes: attributes }
      yield
    end
  end

  class RecordingProvider
    def initialize(tracer)
      @tracer = tracer
    end

    def tracer(_name)
      @tracer
    end
  end

  class Projection < Stweak::Domain::Projection
    def apply(_event); end
    def reset; end
  end

  class EventStore
    include Stweak::Ports::EventStore

    def read_stream(owner_type:, stream_id:, after: 0)
      []
    end

    def append(owner_type:, stream_id:, expected_version:, events:); end
    def each_stream; end
  end

  class CheckpointStore
    include Stweak::Ports::CheckpointStore

    def get(owner_type:, owner_id:)
      nil
    end

    def put(owner_type:, owner_id:, checkpoint:); end
  end

  class Usernames
    include Stweak::Ports::Usernames

    def include?(_username)
      false
    end
  end

  class Hasher
    include Stweak::Domain::Security::PasswordHasher

    def digest(password:)
      'digest'
    end
  end

  class Subscription
    include Stweak::Ports::EventSubscription

    def register(listener:); end
  end

  class ProjectionStore
    include Stweak::Ports::ProjectionStore

    def transaction
      yield
    end

    def read(projection_name:)
      {}
    end

    def write(projection_name:, cursors:); end
    def advance(projection_name:, cursors:); end
    def delete(projection_name:); end
  end
end

RSpec.describe App::Observability::Domain do
  subject(:tracer) { DomainObservabilityDoubles::RecordingTracer.new }

  let(:provider) { DomainObservabilityDoubles::RecordingProvider.new(tracer) }
  let(:account_id) do
    Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001')
  end
  let(:command) do
    Stweak::Domain::Accounts::CreateAccount.new(
      account_id: account_id, username: 'alice', password: 'secret', name: 'Alice', email: 'alice@example.com'
    )
  end
  let(:event_store) { DomainObservabilityDoubles::EventStore.new }
  let(:checkpoint_store) { DomainObservabilityDoubles::CheckpointStore.new }
  let(:usernames) { DomainObservabilityDoubles::Usernames.new }
  let(:handler) do
    Stweak::Domain::Accounts::CreateAccountHandler.new(
      event_store: event_store,
      password_hasher: DomainObservabilityDoubles::Hasher.new,
      checkpoint_store: checkpoint_store,
      usernames: usernames
    )
  end

  before do
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(provider)
    described_class.install
  end

  it 'installs wrappers only once' do
    described_class.install

    aggregate_failures do
      expect(Stweak::Domain::Accounts::Account.ancestors.count(App::Observability::Domain::AccountTracing)).to eq(1)
      expect(Stweak::Domain::Accounts::CreateAccountHandler.ancestors.count(
               App::Observability::Domain::CreateAccountHandlerTracing
             )).to eq(1)
      expect(Stweak::Domain::ProjectionSystem.ancestors.count(App::Observability::Domain::ProjectionSystemTracing))
        .to eq(1)
      expect(Stweak::Domain::Aggregate.singleton_class.ancestors.count(App::Observability::Domain::AggregateTracing))
        .to eq(1)
    end
  end

  it 'traces account creation through the handler, replay, and aggregate' do
    result = handler.handle(command)

    aggregate_failures do
      expect(result.created).to be(true)
      expect(tracer.spans.map { |span| span[:name] }).to include(
        'domain.account.create', 'domain.aggregate.replay', 'domain.account.apply_create'
      )
      expect(tracer.spans.find { |span| span[:name] == 'domain.account.create' }[:attributes]).to include(
        'stweak.command' => 'Stweak::Domain::Accounts::CreateAccount',
        'stweak.account_id' => account_id.to_s
      )
    end
  end

  it 'traces aggregate replay with and without a checkpoint' do
    checkpoint = Stweak::Domain::Checkpoint.new(
      state: { 'created' => false, 'username' => '', 'password_hash' => '', 'name' => '', 'email' => '' }, version: 4
    )
    Stweak::Domain::Accounts::Account.replay(id: account_id, events: [])
    Stweak::Domain::Accounts::Account.replay(id: account_id, events: [], checkpoint: checkpoint)

    checkpointed = tracer.spans.select { |span| span[:name] == 'domain.aggregate.replay' }.map do |span|
      span[:attributes].fetch('stweak.checkpointed')
    end
    expect(checkpointed).to eq([false, true])
  end

  it 'traces projection registration, rebuilding, and event delivery' do
    system = Stweak::Domain::ProjectionSystem.new(
      event_store: DomainObservabilityDoubles::EventStore.new,
      projection_store: DomainObservabilityDoubles::ProjectionStore.new,
      subscription: DomainObservabilityDoubles::Subscription.new
    )
    projection = DomainObservabilityDoubles::Projection.new

    system.register(projection)
    system.rebuild(projection)
    system.on_events_appended(events: [])

    expect(tracer.spans.map { |span| span[:name] }).to include(
      'domain.projection.register', 'domain.projection.rebuild', 'domain.projection.on_events_appended'
    )
  end

  it 'preserves domain errors' do
    usernames.define_singleton_method(:include?) { |_username| true }

    expect { handler.handle(command) }.to raise_error(Stweak::Domain::Accounts::UsernameTaken)
  end
end

# rubocop:enable Style/Documentation
# rubocop:enable Lint/UnusedMethodArgument
# rubocop:enable RSpec/MultipleMemoizedHelpers
# rubocop:enable RSpec/ExampleLength
