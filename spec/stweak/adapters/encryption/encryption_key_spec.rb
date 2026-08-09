# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/adapters/encryption/encryption_key'

RSpec.describe Stweak::Adapters::Encryption::EncryptionKey do
  subject(:key) { described_class.new(value: bytes) }

  let(:bytes) { 'k' * 32 }

  it 'exposes the raw bytes as its stored form' do
    expect(key.to_stored).to eq(bytes)
  end

  it 'masks itself when rendered as a string' do
    expect(key.to_s).to eq('*****')
  end

  it 'masks itself when inspected' do
    expect(key.inspect).to eq('*****')
  end

  it 'refuses an empty key' do
    expect { described_class.new(value: '') }.to raise_error(ArgumentError, /32 bytes/)
  end

  it 'refuses a key shorter than 32 bytes' do
    expect { described_class.new(value: 'k' * 31) }.to raise_error(ArgumentError, /32 bytes/)
  end

  it 'refuses a key longer than 32 bytes' do
    expect { described_class.new(value: 'k' * 33) }.to raise_error(ArgumentError, /32 bytes/)
  end

  it 'is equal to another key with the same bytes' do
    expect(key).to eq(described_class.new(value: bytes))
  end

  it 'is not equal to a key with different bytes' do
    expect(key).not_to eq(described_class.new(value: 'j' * 32))
  end

  it 'is not equal to a bare string with the same bytes' do
    expect(key).not_to eq(bytes)
  end

  it 'is eql to another key with the same bytes' do
    expect(key.eql?(described_class.new(value: bytes))).to be(true)
  end

  it 'is not eql to a key with different bytes' do
    expect(key.eql?(described_class.new(value: 'j' * 32))).to be(false)
  end

  it 'works as a hash key' do
    expect({ key => :found }[described_class.new(value: bytes)]).to eq(:found)
  end
end
