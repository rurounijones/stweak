# typed: false
# frozen_string_literal: true

require 'prop_check'

RSpec.describe Stweak do
  describe '.version' do
    it 'returns the gem version' do
      expect(described_class.version).to eq(Stweak::VERSION)
    end

    it 'returns a semantic version string' do
      expect(described_class.version).to match(/\A\d+\.\d+\.\d+\z/)
    end

    # A property rather than an example: whatever the version happens to be,
    # reading it must never mutate it. This is deliberately modest, and exists
    # to prove the prop_check wiring works before the domain gives it
    # something worth saying. See "Property-based testing, as research" in
    # README.md.
    it 'is stable across any number of reads' do
      PropCheck.forall(PropCheck::Generators.choose(1..20)) do |reads|
        results = Array.new(reads) { described_class.version }

        expect(results.uniq).to eq([Stweak::VERSION])
      end
    end
  end
end
