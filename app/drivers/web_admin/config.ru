# typed: false
# frozen_string_literal: true

require 'dotenv'
Dotenv.load

# Enable OpenTelemetry tracing only when an OTLP endpoint is configured (in the
# shared .env). Configured before the Sinatra app is built and run, so use_all's
# Rack instrumentation wraps every route, with the AWS SDK and Redis calls it
# makes appearing as child spans. Unset means no exporter and no tracing.
unless ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', '').empty?
  # Sinatra must be loaded before configure so use_all detects it and installs
  # the instrumentation that inserts the Rack tracing middleware; the app class
  # (WebAdmin::App) is then defined by the requires below, after the install, so
  # it picks the middleware up. Loading Sinatra after configure would silently
  # leave the routes untraced.
  require 'sinatra/base'
  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
  require 'opentelemetry/instrumentation/all'
  # Load redis before configure for the same reason as Sinatra above: use_all's
  # Redis instrumentation detects RedisClient (redis 5+ does its I/O through it)
  # and registers its middleware only if it is already loaded. Required later, in
  # the wiring, the key-store calls would install too late and go untraced.
  require 'redis'
  # Register app instrumentation before use_all, so it installs alongside the
  # off-the-shelf libraries (SQLite has no published gem of its own).
  require_relative '../../adapters/observability/sqlite_instrumentation'
  require_relative '../../observability/domain'
  require_relative '../../observability/adapters'
  OpenTelemetry::SDK.configure do |c|
    c.service_name = 'stweak-web-admin'
    c.use_all
  end
  # On recent aws-sdk-core the instrumentation defers to the SDK's own telemetry
  # plugin, which stays a no-op until a provider is set. Point it at
  # OpenTelemetry so the DynamoDB client spans are emitted, nesting under the
  # named adapter spans. Clients built by the wiring inherit it.
  Aws.config[:telemetry_provider] = Aws::Telemetry::OTelProvider.new
  App::Observability::Domain.install
  App::Observability::Adapters.install
end

require_relative 'lib/wiring'
require_relative 'lib/web_admin'

# Building the reader constructs the stores, whose setup calls (creating the
# DynamoDB table, etc.) happen before any request span. Wrap them in one boot
# span so they do not surface as orphaned client spans.
reader =
  if ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', '').empty?
    WebAdmin::Wiring.reader
  else
    OpenTelemetry.tracer_provider
                 .tracer('stweak-web-admin')
                 .in_span('web_admin.boot', attributes: { 'code.function' => 'main#reader' }) { WebAdmin::Wiring.reader }
  end

WebAdmin::App.set(:reader, reader)
run WebAdmin::App
