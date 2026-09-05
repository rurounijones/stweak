# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/username'
# A subclass, to pin that equality is by exact class: a username and a subclass
# instance with the same value are unequal, and unequal both ways round.
class SubUsername < Stweak::Domain::Accounts::Username; end

RSpec.describe Stweak::Domain::Accounts::Username do
  subject(:username) { described_class.new(value: 'ada') }

  it 'holds the value' do
    expect(username.value).to eq('ada')
  end

  it 'renders the value as a string' do
    expect(username.to_s).to eq('ada')
  end

  it 'accepts letters, digits, underscore and hyphen' do
    expect(described_class.new(value: 'Ada_99-x').value).to eq('Ada_99-x')
  end

  it 'accepts the shortest and longest allowed lengths' do
    expect([described_class.new(value: 'abc').value, described_class.new(value: 'a' * 30).value])
      .to eq(['abc', 'a' * 30])
  end

  it 'rejects an empty value' do
    expect { described_class.new(value: '') }
      .to raise_error(Stweak::Domain::ValidationError, /3 to 30 characters/)
  end

  it 'rejects a value shorter than three characters' do
    expect { described_class.new(value: 'ab') }
      .to raise_error(Stweak::Domain::ValidationError, /3 to 30 characters/)
  end

  it 'rejects a value longer than thirty characters' do
    expect { described_class.new(value: 'a' * 31) }
      .to raise_error(Stweak::Domain::ValidationError, /3 to 30 characters/)
  end

  it 'rejects whitespace' do
    expect { described_class.new(value: 'ad a') }
      .to raise_error(Stweak::Domain::ValidationError, /letters, digits/)
  end

  it 'rejects punctuation outside underscore and hyphen' do
    expect { described_class.new(value: 'ada.b') }
      .to raise_error(Stweak::Domain::ValidationError, /letters, digits/)
  end

  it 'names the bad value in the rejection, since a username is not personal data' do
    expect { described_class.new(value: 'ad a') }
      .to raise_error(Stweak::Domain::ValidationError, /"ad a"/)
  end

  it 'rejects a value that is not valid UTF-8' do
    expect { described_class.new(value: "abc\xFF") }
      .to raise_error(Stweak::Domain::ValidationError, /letters, digits/)
  end

  it 'is equal to a username with the same value' do
    expect(username).to eq(described_class.new(value: 'ada'))
  end

  it 'is not equal to a subclass with the same value, symmetrically' do
    sub = SubUsername.new(value: 'ada')
    expect([username == sub, sub == username]).to all(be(false))
  end

  it 'is not equal to a username with a different value' do
    expect(username == described_class.new(value: 'grace')).to be(false)
  end

  it 'is not equal to a non-username' do
    expect(username == Object.new).to be(false)
  end

  it 'is eql to a username with the same value' do
    expect(username.eql?(described_class.new(value: 'ada'))).to be(true)
  end

  it 'hashes to the value hash' do
    expect(username.hash).to eq('ada'.hash)
  end
end
