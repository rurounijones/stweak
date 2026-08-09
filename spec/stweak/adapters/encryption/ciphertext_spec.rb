# typed: false
# frozen_string_literal: true

require 'base64'
require_relative '../../../../lib/stweak/adapters/encryption/ciphertext'

RSpec.describe Stweak::Adapters::Encryption::Ciphertext do
  subject(:ciphertext) { described_class.new(value: stored) }

  let(:nonce) { 'nonce-bytes' }
  let(:tag) { 'tag-bytes' }
  let(:data) { 'ciphertext-bytes' }
  let(:stored) { [nonce, tag, data].map { |part| Base64.strict_encode64(part) }.join('.') }
  let(:empty_data_ciphertext) do
    described_class.new(value: [nonce, tag, ''].map { |part| Base64.strict_encode64(part) }.join('.'))
  end

  it 'exposes the decoded nonce' do
    expect(ciphertext.nonce).to eq(nonce)
  end

  it 'exposes the decoded tag' do
    expect(ciphertext.tag).to eq(tag)
  end

  it 'exposes the decoded data' do
    expect(ciphertext.data).to eq(data)
  end

  it 'round-trips its stored form' do
    expect(ciphertext.to_stored).to eq(stored)
  end

  it 'renders its stored form as a string' do
    expect(ciphertext.to_s).to eq(stored)
  end

  it 'keeps an empty data segment' do
    expect(empty_data_ciphertext.data).to eq('')
  end

  it 'stores an empty data segment with its trailing separator' do
    expect(empty_data_ciphertext.to_stored).to end_with('.')
  end

  it 'refuses a value with no separators' do
    expect { described_class.new(value: 'not-a-valid-ciphertext') }
      .to raise_error(ArgumentError, /malformed/)
  end

  it 'refuses a ciphertext of two segments' do
    expect { described_class.new(value: 'YQ==.Yg==') }.to raise_error(ArgumentError, /malformed/)
  end

  it 'refuses a ciphertext of four segments' do
    expect { described_class.new(value: 'YQ==.Yg==.Yw==.ZA==') }.to raise_error(ArgumentError, /malformed/)
  end

  it 'refuses a segment that is not base64' do
    expect { described_class.new(value: 'YQ==.Yg==.!!!!') }.to raise_error(ArgumentError)
  end

  it 'is equal to another ciphertext with the same envelope' do
    expect(ciphertext).to eq(described_class.new(value: stored))
  end

  it 'is not equal to a ciphertext with different data' do
    other = [nonce, tag, 'other'].map { |part| Base64.strict_encode64(part) }.join('.')

    expect(ciphertext).not_to eq(described_class.new(value: other))
  end

  it 'is not equal to a bare string with the same envelope' do
    expect(ciphertext).not_to eq(stored)
  end

  it 'is eql to another ciphertext with the same envelope' do
    expect(ciphertext.eql?(described_class.new(value: stored))).to be(true)
  end

  it 'is not eql to a ciphertext with different data' do
    other = [nonce, tag, 'other'].map { |part| Base64.strict_encode64(part) }.join('.')

    expect(ciphertext.eql?(described_class.new(value: other))).to be(false)
  end

  it 'works as a hash key' do
    expect({ ciphertext => :found }[described_class.new(value: stored)]).to eq(:found)
  end
end
