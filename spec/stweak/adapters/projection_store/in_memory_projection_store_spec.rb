# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/adapters/projection_store/in_memory'
require_relative '../../../support/projection_store_examples'

RSpec.describe Stweak::Adapters::ProjectionStore::InMemoryProjectionStore do
  subject(:store) { described_class.new }

  it_behaves_like 'a projection store'
end
