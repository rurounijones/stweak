# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/id'
# A subclass, to pin that equality is by value and not by exact class.
class SubId < Stweak::Domain::Id; end

RSpec.describe Stweak::Domain::Id do
  subject(:id) { described_class.new(value: uuid) }

  let(:uuid) { '00000000-0000-4000-8000-000000000001' }

  it 'holds the value' do
    expect(id.value).to eq(uuid)
  end

  it 'renders the value as a string' do
    expect(id.to_s).to eq(uuid)
  end

  it 'rejects a non-UUID, naming the bad value in quotes' do
    expect { described_class.new(value: 'not-a-uuid') }
      .to raise_error(Stweak::Domain::ValidationError, /"not-a-uuid"/)
  end

  it 'rejects a value that is not valid UTF-8' do
    expect { described_class.new(value: "\xFF") }
      .to raise_error(Stweak::Domain::ValidationError, /UUID/)
  end

  it 'is equal to an id with the same value' do
    expect(id).to eq(described_class.new(value: uuid))
  end

  it 'is equal to a subclass with the same value' do
    expect(id).to eq(SubId.new(value: uuid))
  end

  it 'is not equal to an id with a different value' do
    expect(id == described_class.new(value: '00000000-0000-4000-8000-000000000002')).to be(false)
  end

  it 'is not equal to a non-id' do
    expect(id == Object.new).to be(false)
  end

  it 'is eql to an id with the same value' do
    expect(id.eql?(described_class.new(value: uuid))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(id.hash).to eq(uuid.hash)
  end
end
