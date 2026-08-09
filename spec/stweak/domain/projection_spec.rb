# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/projection'

# A namespaced concrete projection, so the name derivation can be shown to
# strip the namespace.
module SampleNamespace
  class Projection < Stweak::Domain::Projection
    def apply(_event); end

    def reset; end
  end
end

# A top-level concrete projection, so the name derivation is pinned for a
# single-segment class name too.
class TopLevelProjection < Stweak::Domain::Projection
  def apply(_event); end

  def reset; end
end

RSpec.describe Stweak::Domain::Projection do
  it 'derives a stable name from a namespaced class' do
    expect(SampleNamespace::Projection.new.name).to eq('Projection')
  end

  it 'derives a stable name from a top-level class' do
    expect(TopLevelProjection.new.name).to eq('TopLevelProjection')
  end
end
