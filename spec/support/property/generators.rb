# typed: false
# frozen_string_literal: true

require 'prop_check'

# Shared generators for property-based tests. Everything here is a
# domain-independent building block — a UUID, a string, an AES key, a time —
# that the domain-specific generators in this directory compose. A spec
# includes this module to get these generators (and prop_check's built-ins)
# as methods.
module PropertyGenerators
  include PropCheck::Generators

  # A lowercase UUID with the canonical dash layout, as AccountId demands.
  def uuid
    array(choose(0..15).map { |digit| digit.to_s(16) }, min: 32, max: 32).map do |parts|
      digits = parts.join
      [digits[0, 8], digits[8, 4], digits[12, 4], digits[16, 4], digits[20, 12]].join('-')
    end
  end

  # A string of at least one character.
  def nonempty_string
    string(min: 1)
  end

  # A 32-byte AES-256 key.
  def aes_key
    array(choose(0..255), min: 32, max: 32).map { |bytes| bytes.pack('C*') }
  end

  # A time, for occurred-at fields. The range stays within Time's safe span.
  def time
    choose(0..4_000_000_000).map { |seconds| Time.at(seconds) }
  end
end
