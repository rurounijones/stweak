# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/projection_name'
# A subclass, to pin that equality is by exact class: a projection name and a
# subclass instance with the same value are unequal, and unequal both ways round.
class SubProjectionName < Stweak::Domain::ProjectionName; end

RSpec.describe Stweak::Domain::ProjectionName do
  subject(:projection_name) { described_class.new(value: 'AccountsProjector') }

  it 'holds the value' do
    expect(projection_name.value).to eq('AccountsProjector')
  end

  it 'renders the value as a string' do
    expect(projection_name.to_s).to eq('AccountsProjector')
  end

  it 'accepts a single letter and a name with digits' do
    expect([described_class.new(value: 'A').value, described_class.new(value: 'Projector2').value])
      .to eq(%w[A Projector2])
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects a value that starts with a digit' do
    expect { described_class.new(value: '1Projector') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects whitespace' do
    expect { described_class.new(value: 'Accounts Projector') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects underscore, hyphen and other punctuation' do
    expect { described_class.new(value: 'Accounts_Projector') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'names the bad value in the rejection' do
    expect { described_class.new(value: 'Bad Name') }
      .to raise_error(Stweak::Domain::ValidationError, /"Bad Name"/)
  end

  it 'rejects a value that is not valid UTF-8' do
    expect { described_class.new(value: "Abc\xFF") }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'is equal to a projection name with the same value' do
    expect(projection_name).to eq(described_class.new(value: 'AccountsProjector'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubProjectionName.new(value: 'AccountsProjector')
    expect([projection_name == sub, sub == projection_name]).to all(be(false))
  end

  it 'is not equal to a projection name with a different value' do
    expect(projection_name == described_class.new(value: 'UsernamesProjector')).to be(false)
  end

  it 'is not equal to a non-projection-name' do
    expect(projection_name == 'AccountsProjector').to be(false)
  end

  it 'is eql to a projection name with the same value' do
    expect(projection_name.eql?(described_class.new(value: 'AccountsProjector'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(projection_name.hash).to eq('AccountsProjector'.hash)
  end
end
