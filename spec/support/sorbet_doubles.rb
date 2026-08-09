# typed: false
# frozen_string_literal: true

require 'sorbet-runtime'

# Unit tests mock their dependencies rather than reaching for a real adapter,
# per the performant-testing goal: a true unit isolates its subject and lets the
# suite — and the mutation runs that multiply it — stay fast. RSpec's verifying
# doubles are the tool, but sorbet-runtime validates a `sig`'s parameter types
# at the call boundary and rejects a double as the wrong class before the stub
# is ever reached.
#
# This teaches sorbet-runtime to treat a verifying double as satisfying the
# type it stands in for. A verifying double already checks that every message
# it answers exists on the class it doubles, so the signature guarantee is not
# lost — it is enforced by RSpec instead of by the runtime check. Non-double
# type errors still raise as before.
module SorbetDoubles
  DOUBLE_CLASSES = [
    RSpec::Mocks::Double,
    RSpec::Mocks::InstanceVerifyingDouble,
    RSpec::Mocks::ObjectVerifyingDouble,
    RSpec::Mocks::ClassVerifyingDouble
  ].freeze

  def self.double?(value)
    DOUBLE_CLASSES.any? { |klass| value.is_a?(klass) }
  end
end

previous_handler = T::Configuration.instance_variable_get(:@inline_type_error_handler)

T::Configuration.inline_type_error_handler = lambda do |error, opts|
  raise error unless SorbetDoubles.double?(opts[:value])
end

T::Configuration.call_validation_error_handler = lambda do |_signature, opts|
  raise TypeError, opts[:pretty_message] unless SorbetDoubles.double?(opts[:value])
end

at_exit do
  T::Configuration.inline_type_error_handler = previous_handler
end
