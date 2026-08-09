# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/projection'

# A concrete projection that declares its name, as every projection must.
class DeclaredProjection < Stweak::Domain::Projection
  NAME = Stweak::Domain::ProjectionName.new(value: 'Declared')

  def name
    NAME
  end

  def apply(_event); end

  def reset; end
end

# A concrete projection that omits its name, to pin that name is required.
class UnnamedProjection < Stweak::Domain::Projection
  def apply(_event); end

  def reset; end
end

RSpec.describe Stweak::Domain::Projection do
  it 'returns the name the projection declares' do
    expect(DeclaredProjection.new.name).to eq(Stweak::Domain::ProjectionName.new(value: 'Declared'))
  end

  it 'requires each projection to declare its name' do
    expect { UnnamedProjection.new.name }.to raise_error(NotImplementedError)
  end
end
