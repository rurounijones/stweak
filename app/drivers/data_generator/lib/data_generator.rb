# typed: strict
# frozen_string_literal: true

require 'opentelemetry'
require 'sorbet-runtime'
require 'stweak'
require_relative 'commands'

module DataGenerator
  # The generator: a caller that wraps the domain and produces plausible
  # account-creation events in volume, driving the same CreateAccountHandler
  # an HTTP API would. It exists to stress-test the system and to build
  # projections against before any real traffic exists. The wiring (which
  # adapters back the handler) is supplied by the caller — see Wiring.
  class Generator
    extend T::Sig

    # @param handler [Stweak::Domain::Accounts::CreateAccountHandler]
    # @param event_store [Stweak::Ports::EventStore] exposed for the caller to
    #   verify what was written
    sig do
      params(
        handler: Stweak::Domain::Accounts::CreateAccountHandler,
        event_store: Stweak::Ports::EventStore
      ).void
    end
    def initialize(handler:, event_store:)
      @handler = handler
      @event_store = event_store
      # A no-op tracer unless an SDK has been configured at boot (see
      # bin/stweak-generate), so the spans below cost nothing with tracing off.
      @tracer = T.let(
        OpenTelemetry.tracer_provider.tracer('stweak-data-generator'),
        OpenTelemetry::Trace::Tracer
      )
    end

    # Create count accounts with random usernames and display names.
    #
    # @param count [Integer]
    # @return [Array<Stweak::Domain::Accounts::Account>] the created accounts
    sig { params(count: Integer).returns(T::Array[Stweak::Domain::Accounts::Account]) }
    def run(count)
      Array.new(count) do
        @tracer.in_span(
          'data_generator.create_account',
          attributes: { 'code.function' => 'DataGenerator::Generator#run' }
        ) do |span|
          @handler.handle(random_command).tap do |account|
            span.set_attribute('stweak.account_id', account.id.value)
          end
        end
      end
    end

    # Every event written by the generator, for verifying the run.
    #
    # @return [Array<Stweak::Domain::Event>]
    sig { returns(T::Array[Stweak::Domain::Event]) }
    def events
      events = []
      @event_store.each_stream do |_owner_type, _stream_id, stream_events|
        events.concat(stream_events)
      end
      events
    end

    private

    # A plausible create-account command, shared with the LifecycleGenerator
    # so both generators drive the domain the same way (see DataGenerator::Commands).
    #
    # @return [Stweak::Domain::Accounts::CreateAccount]
    sig { returns(Stweak::Domain::Accounts::CreateAccount) }
    def random_command
      DataGenerator::Commands.random_create
    end
  end
end
