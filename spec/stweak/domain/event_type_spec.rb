# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/event_type'
# A subclass, to pin that equality is by exact class: an event type and a
# subclass instance with the same value are unequal, and unequal both ways round.
class SubEventType < Stweak::Domain::EventType; end

RSpec.describe Stweak::Domain::EventType do
  subject(:event_type) { described_class.new(value: 'AccountCreated') }

  it 'holds the value' do
    expect(event_type.value).to eq('AccountCreated')
  end

  it 'renders the value as a string' do
    expect(event_type.to_s).to eq('AccountCreated')
  end

  it 'accepts a single letter and a name with digits' do
    expect([described_class.new(value: 'A').value, described_class.new(value: 'Event2').value])
      .to eq(%w[A Event2])
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects a value that starts with a digit' do
    expect { described_class.new(value: '1Event') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects whitespace' do
    expect { described_class.new(value: 'Account Created') }
      .to raise_error(Stweak::Domain::ValidationError, /letters and digits/)
  end

  it 'rejects underscore, hyphen and other punctuation' do
    expect { described_class.new(value: 'Account_Created') }
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

  it 'is equal to an event type with the same value' do
    expect(event_type).to eq(described_class.new(value: 'AccountCreated'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubEventType.new(value: 'AccountCreated')
    expect([event_type == sub, sub == event_type]).to all(be(false))
  end

  it 'is not equal to an event type with a different value' do
    expect(event_type == described_class.new(value: 'AccountDeleted')).to be(false)
  end

  it 'is not equal to a non-event-type' do
    expect(event_type == 'AccountCreated').to be(false)
  end

  it 'is eql to an event type with the same value' do
    expect(event_type.eql?(described_class.new(value: 'AccountCreated'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(event_type.hash).to eq('AccountCreated'.hash)
  end
end
