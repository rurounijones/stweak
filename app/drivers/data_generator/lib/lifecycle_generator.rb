# typed: strict
# frozen_string_literal: true

require 'net/http'
require 'opentelemetry'
require 'sorbet-runtime'
require 'stweak'
require_relative 'commands'

module DataGenerator
  # Drives the full account lifecycle continuously: each worker thread creates
  # an account, disables it, then deletes it — exercising AccountDisabled and
  # AccountDeleted as well as creation — with a short random gap between
  # actions, then repeats until #stop is called. Where the bounded Generator
  # creates a fixed batch and exits, this is the generator the trace helpers
  # run: it keeps producing events (and, with check_web_admin:, read traffic)
  # until interrupted, so a demo can watch the lifecycle unfold on a trace
  # timeline.
  #
  # Spawning its own worker threads is the point of the class, and each
  # span-wrapped action is documented inline, so the class deliberately
  # exceeds RuboCop's default size and its new-thread rule.
  # rubocop:disable Metrics/ClassLength
  # rubocop:disable ThreadSafety/NewThread
  class LifecycleGenerator
    extend T::Sig

    # How many lifecycle workers run unless told otherwise.
    DEFAULT_THREADS = 3

    # The gap between a worker's create, disable and delete actions, which
    # spaces a lifecycle out on the trace timeline. Injectable so a caller
    # (a spec) can drive cycles without waiting.
    DEFAULT_GAP = (1..5)

    # How long a web-admin checker waits between requests to the read side.
    WEB_ADMIN_INTERVAL = (5..7)

    # Where the web admin listens when the checker is on.
    WEB_ADMIN_URL = 'http://127.0.0.1:4567/'

    # @param create_handler [Stweak::Domain::Accounts::CreateAccountHandler]
    # @param disable_handler [Stweak::Domain::Accounts::DisableAccountHandler]
    # @param delete_handler [Stweak::Domain::Accounts::DeleteAccountHandler]
    # @param gap [Range] the seconds between a worker's actions
    # @param web_admin_url [String] the web admin the checker requests
    sig do
      params(
        create_handler: Stweak::Domain::Accounts::CreateAccountHandler,
        disable_handler: Stweak::Domain::Accounts::DisableAccountHandler,
        delete_handler: Stweak::Domain::Accounts::DeleteAccountHandler,
        gap: T::Range[Integer],
        web_admin_url: String
      ).void
    end
    def initialize(
      create_handler:,
      disable_handler:,
      delete_handler:,
      gap: DEFAULT_GAP,
      web_admin_url: WEB_ADMIN_URL
    )
      @create_handler = create_handler
      @disable_handler = disable_handler
      @delete_handler = delete_handler
      @gap = gap
      @web_admin_url = web_admin_url
      @stopped = T.let(false, T::Boolean)
      # A no-op tracer unless an SDK has been configured at boot (see
      # bin/stweak-generate), so the spans below cost nothing with tracing off.
      @tracer = T.let(
        OpenTelemetry.tracer_provider.tracer('stweak-data-generator'),
        OpenTelemetry::Trace::Tracer
      )
    end

    # Run lifecycle workers — and, when check_web_admin is true, a checker
    # thread that requests the web admin — until #stop is called. Blocks the
    # calling thread; a signal handler or another thread stops it.
    #
    # @param thread_count [Integer] the number of lifecycle workers
    # @param check_web_admin [Boolean] whether to drive the read side too
    # @return [void]
    sig { params(thread_count: Integer, check_web_admin: T::Boolean).void }
    def run(thread_count:, check_web_admin: false)
      threads = Array.new(thread_count) { Thread.new { worker_loop } }
      threads << Thread.new { web_admin_checker_loop } if check_web_admin
      threads.each(&:join)
    end

    # Ask the workers to stop after their current action. Returns true when
    # this call is what stopped the generator, false if it had already stopped.
    #
    # @return [Boolean]
    sig { returns(T::Boolean) }
    def stop
      returning = !@stopped
      @stopped = true
      returning
    end

    # One full lifecycle: create an account, disable it, then delete it. Public
    # so a caller can drive a single cycle deterministically; a worker loop is
    # just this repeated until stopped.
    #
    # @return [Stweak::Domain::Accounts::Account] the account, deleted by the
    #   time this returns
    sig { returns(Stweak::Domain::Accounts::Account) }
    def run_cycle
      account = create_account
      interruptible_sleep(random_gap)
      disable_account(account.id)
      interruptible_sleep(random_gap)
      delete_account(account.id)
    end

    private

    # The steady loop behind each worker thread.
    sig { void }
    def worker_loop
      run_cycle until @stopped
    end

    # The checker thread: keep the read side warm so its route spans appear
    # alongside the write-side lifecycle, tolerating the web admin being down
    # (still starting, or already stopped).
    sig { void }
    def web_admin_checker_loop
      until @stopped
        check_web_admin
        interruptible_sleep(rand(WEB_ADMIN_INTERVAL))
      end
    end

    # Create an account, emitting one span that parents the domain and store
    # spans the create produces.
    #
    # @return [Stweak::Domain::Accounts::Account]
    sig { returns(Stweak::Domain::Accounts::Account) }
    def create_account
      @tracer.in_span(
        'data_generator.create_account',
        attributes: { 'code.function' => 'DataGenerator::LifecycleGenerator#run_cycle' }
      ) do |span|
        @create_handler.handle(Commands.random_create).tap do |account|
          span.set_attribute('stweak.account_id', account.id.value)
        end
      end
    end

    # Disable the account, emitting the same span shape as create.
    #
    # @param account_id [Stweak::Domain::Accounts::AccountId]
    # @return [Stweak::Domain::Accounts::Account]
    sig { params(account_id: Stweak::Domain::Accounts::AccountId).returns(Stweak::Domain::Accounts::Account) }
    def disable_account(account_id)
      @tracer.in_span(
        'data_generator.disable_account',
        attributes: { 'code.function' => 'DataGenerator::LifecycleGenerator#run_cycle' }
      ) do |span|
        @disable_handler.handle(Commands.disable(account_id)).tap do |account|
          span.set_attribute('stweak.account_id', account.id.value)
        end
      end
    end

    # Delete the account, emitting the same span shape as create and disable.
    #
    # @param account_id [Stweak::Domain::Accounts::AccountId]
    # @return [Stweak::Domain::Accounts::Account]
    sig { params(account_id: Stweak::Domain::Accounts::AccountId).returns(Stweak::Domain::Accounts::Account) }
    def delete_account(account_id)
      @tracer.in_span(
        'data_generator.delete_account',
        attributes: { 'code.function' => 'DataGenerator::LifecycleGenerator#run_cycle' }
      ) do |span|
        @delete_handler.handle(Commands.delete(account_id)).tap do |account|
          span.set_attribute('stweak.account_id', account.id.value)
        end
      end
    end

    # Request the web admin's list page so the read side is exercised
    # throughout the run. Returns the response code, or nil when the web admin
    # is not reachable. With tracing on, the Net::HTTP instrumentation adds a
    # client span under the generator's own span and propagates the trace
    # context, so the web admin's route span (a different process) parents
    # under this one.
    #
    # @return [String, nil]
    sig { returns(T.nilable(String)) }
    def check_web_admin
      @tracer.in_span(
        'data_generator.web_admin_check',
        attributes: { 'code.function' => 'DataGenerator::LifecycleGenerator#web_admin_checker_loop' }
      ) do |span|
        response = Net::HTTP.get_response(URI(@web_admin_url))
        span.set_attribute('http.response.status_code', response.code.to_i)
        response.code
      end
    rescue StandardError
      nil
    end

    # Sleep for a number of seconds, waking early when the generator is
    # stopped so Ctrl-C or TERM is answered promptly rather than at the end of
    # the current gap.
    #
    # @param seconds [Numeric]
    sig { params(seconds: Numeric).void }
    def interruptible_sleep(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      sleep 0.1 until @stopped || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end

    # @return [Integer] the seconds to wait between a worker's actions
    sig { returns(Integer) }
    def random_gap
      rand(@gap)
    end
  end
  # rubocop:enable Metrics/ClassLength
  # rubocop:enable ThreadSafety/NewThread
end
