# typed: false
# frozen_string_literal: true

require_relative '../../../lib/stweak/domain/stream_key'
# A subclass, to pin that equality is by exact class: a stream key and a
# subclass instance with the same value are unequal, and unequal both ways round.
class SubStreamKey < Stweak::Domain::StreamKey; end

RSpec.describe Stweak::Domain::StreamKey do
  subject(:stream_key) { described_class.new(value: value) }

  let(:value) { 'Stweak::Domain::Accounts::Account#00000000-0000-4000-8000-000000000001' }

  it 'holds the value' do
    expect(stream_key.value).to eq(value)
  end

  it 'renders the value as a string' do
    expect(stream_key.to_s).to eq(value)
  end

  it 'accepts a bare owner name' do
    expect(described_class.new(value: 'Account#00000000-0000-4000-8000-000000000001').value)
      .to eq('Account#00000000-0000-4000-8000-000000000001')
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects an owner that does not start with a capital letter' do
    expect { described_class.new(value: 'account#00000000-0000-4000-8000-000000000001') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects a namespace segment that starts with a digit' do
    expect { described_class.new(value: 'Stweak::1Account#00000000-0000-4000-8000-000000000001') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects whitespace in the owner' do
    expect { described_class.new(value: 'Stweak Account#00000000-0000-4000-8000-000000000001') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects an id that is not a UUID' do
    expect { described_class.new(value: 'Account#0000') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects an uppercase UUID, as the id type does' do
    expect { described_class.new(value: 'Account#00000000-0000-4000-8000-00000000000A') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects a missing separator' do
    expect { described_class.new(value: 'Account00000000-0000-4000-8000-000000000001') }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects a trailing newline, which a loose anchor would let through' do
    expect { described_class.new(value: "Account#00000000-0000-4000-8000-000000000001\n") }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'rejects a value that is not valid UTF-8' do
    expect { described_class.new(value: "Abc\xFF#00000000-0000-4000-8000-000000000001") }
      .to raise_error(Stweak::Domain::ValidationError, /owner and a UUID/)
  end

  it 'names the bad value in the rejection' do
    expect { described_class.new(value: 'bad') }
      .to raise_error(Stweak::Domain::ValidationError, /"bad"/)
  end

  it 'is equal to a stream key with the same value' do
    expect(stream_key).to eq(described_class.new(value: value))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubStreamKey.new(value: value)
    expect([stream_key == sub, sub == stream_key]).to all(be(false))
  end

  it 'is not equal to a stream key with a different value' do
    other = described_class.new(value: 'Stweak::Domain::Accounts::Account#00000000-0000-4000-8000-000000000002')
    expect(stream_key == other).to be(false)
  end

  it 'is not equal to a non-stream-key' do
    expect(stream_key == value).to be(false)
  end

  it 'is eql to a stream key with the same value' do
    expect(stream_key.eql?(described_class.new(value: value))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(stream_key.hash).to eq(value.hash)
  end
end
