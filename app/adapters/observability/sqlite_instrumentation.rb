# typed: false
# frozen_string_literal: true

require 'opentelemetry'
require 'opentelemetry-instrumentation-base'
require 'sqlite3'

module App
  module Observability
    # OpenTelemetry instrumentation for SQLite, the one store the drivers use
    # that has no published instrumentation gem of its own (Redis, the AWS SDK
    # behind DynamoDB, and Net::HTTP all do). Written as an
    # OpenTelemetry::Instrumentation::Base subclass so that merely requiring
    # this file registers it, and a driver's `use_all` installs it alongside
    # the off-the-shelf ones — SQLite queries then appear as client spans,
    # nested under whatever request or operation issued them, exactly as the
    # Redis and DynamoDB spans do.
    #
    # It patches SQLite3::Database#execute, the single method every read and
    # write in SqliteProjectionStore goes through, and records only the SQL
    # text (which carries `?` placeholders, never the bound values), so no
    # personal data reaches a span.
    class SqliteInstrumentation < OpenTelemetry::Instrumentation::Base
      install { |_config| patch }
      present { defined?(::SQLite3::Database) }

      # Prepend the span-emitting wrapper onto the SQLite driver.
      def patch
        ::SQLite3::Database.prepend(Patch)
      end

      # The leading SQL keyword, e.g. SELECT or INSERT.
      OPERATION = /\A\s*(\w+)/

      # The object the statement acts on, after FROM / INTO / UPDATE / TABLE.
      TARGET = /\b(?:FROM|INTO|UPDATE|TABLE(?:\s+IF\s+NOT\s+EXISTS)?)\s+["'`]?(\w+)/i

      # A concise span name: the operation and its target where one can be
      # read off the statement ("SELECT accounts"), the operation alone
      # otherwise ("BEGIN").
      def self.span_name(sql)
        operation = sql[OPERATION, 1]&.upcase || 'SQL'
        target = sql[TARGET, 1]
        target ? "#{operation} #{target}" : operation
      end

      # The wrapper prepended onto SQLite3::Database. It brackets each execute
      # in a client span carrying the SQL, then delegates unchanged.
      module Patch
        def execute(*args)
          sql = args.first.to_s
          attributes = {
            'db.system' => 'sqlite',
            'db.operation' => sql[OPERATION, 1]&.upcase,
            'db.statement' => sql
          }
          SqliteInstrumentation.instance.tracer.in_span(
            SqliteInstrumentation.span_name(sql),
            attributes: attributes.merge('code.function' => "SQLite3::Database#execute"), kind: :client
          ) { super }
        end
      end
    end
  end
end
