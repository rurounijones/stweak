# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Stweak
  module Domain
    # The value of a field whose owner's encryption key was shredded under a
    # GDPR erasure. The data is gone permanently and by design: reading the
    # field yields ValueMissing rather than raising, because a missing key is
    # a normal state, not an error. A module used as a value, so a field that
    # is encrypted can be either its plain value or ValueMissing — a union
    # that is less ambiguous than a bare nil.
    module ValueMissing
    end
  end
end
