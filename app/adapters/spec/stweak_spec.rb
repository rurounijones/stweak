# typed: false
# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Stweak do
  it 'loads the domain gem' do
    expect(described_class.version).to be_a(String)
  end
end
