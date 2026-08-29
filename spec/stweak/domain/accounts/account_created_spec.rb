# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/owner_registry'

# Concise builders for the account value objects, to keep examples short.
def make_username(value) = Stweak::Domain::Accounts::Username.new(value: value)
def make_display_name(value) = Stweak::Domain::Accounts::DisplayName.new(value: value)
def make_email(value) = Stweak::Domain::Accounts::Email.new(value: value)

RSpec.describe Stweak::Domain::Accounts::AccountCreated do
  subject(:event) do
    described_class.new(**valid_attributes)
  end

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:occurred_at) { Time.utc(2026, 1, 2, 3, 4, 5) }
  let(:serialized) { event.to_h }
  let(:valid_attributes) do
    {
      stream_id: account_id,
      sequence: 1,
      occurred_at: occurred_at,
      account_id: account_id,
      username: make_username('alice'),
      password_hash: 'hash',
      name: make_display_name('Alice'),
      email: make_email('alice@example.com')
    }
  end

  it 'is version 1' do
    expect(event.version).to eq(1)
  end

  it 'reports its type' do
    expect(event.type).to eq('AccountCreated')
  end

  it 'declares the display name and email as its PII fields' do
    expect(described_class.pii_fields).to eq(%i[name email])
  end

  it 'defaults to no PII fields on the base event' do
    expect(Stweak::Domain::Event.pii_fields).to eq([])
  end

  it 'maps to the aggregate class that owns its stream' do
    expect(Stweak::Domain::OwnerRegistry.owner_type_for(described_class))
      .to eq(Stweak::Domain::Accounts::Account)
  end

  it 'is not equal to an event with different fields' do
    other = described_class.new(**valid_attributes, username: make_username('bob'),
                                                    name: make_display_name('Bob'), email: make_email('bob@x.com'))
    expect(event == other).to be(false)
  end

  it 'serializes its type' do
    expect(serialized['type']).to eq('AccountCreated')
  end

  it 'serializes its version' do
    expect(serialized['version']).to eq(1)
  end

  it 'serializes its stream id' do
    expect(serialized['stream_id']).to eq(account_id.to_s)
  end

  it 'serializes its sequence' do
    expect(serialized['sequence']).to eq(1)
  end

  it 'serializes its timestamp' do
    expect(serialized['occurred_at']).to eq(occurred_at.iso8601)
  end

  it 'defaults created_at to occurred_at' do
    expect(event.created_at).to eq(occurred_at)
  end

  it 'serializes its created_at' do
    expect(serialized['created_at']).to eq(occurred_at.iso8601)
  end

  it 'round-trips a created_at distinct from occurred_at' do
    created_at = Time.utc(2026, 2, 3, 4, 5, 6)
    committed = described_class.new(**valid_attributes, created_at: created_at)
    expect(described_class.from_h(committed.to_h)).to eq(committed)
  end

  it 'stores the created_at it was given' do
    created_at = Time.utc(2026, 2, 3, 4, 5, 6)
    committed = described_class.new(**valid_attributes, created_at: created_at)
    expect(committed.created_at).to eq(created_at)
  end

  it 'serializes its account id' do
    expect(serialized['account_id']).to eq(account_id.to_s)
  end

  it 'serializes its username' do
    expect(serialized['username']).to eq('alice')
  end

  it 'serializes its password hash' do
    expect(serialized['password_hash']).to eq('hash')
  end

  it 'serializes its name' do
    expect(serialized['name']).to eq('Alice')
  end

  it 'serializes its email' do
    expect(serialized['email']).to eq('alice@example.com')
  end

  it 'round-trips through its serialized form' do
    rebuilt = described_class.from_h(event.to_h)
    expect(rebuilt).to eq(event)
  end

  it 'is eql to an event with the same fields' do
    rebuilt = described_class.from_h(event.to_h)
    expect(rebuilt.eql?(event)).to be(true)
  end

  it 'hashes to the hash of its serialized form' do
    expect(event.hash).to eq(event.to_h.hash)
  end

  it 'is not equal to a non-event' do
    expect(event == Object.new).to be(false)
  end

  it 'rejects a non-positive sequence' do
    expect { described_class.new(**valid_attributes, sequence: 0) }
      .to raise_error(Stweak::Domain::ValidationError, /sequence/)
  end

  it 'rejects an empty password hash' do
    expect { described_class.new(**valid_attributes, password_hash: '') }
      .to raise_error(Stweak::Domain::ValidationError, /password hash/)
  end

  it 'accepts a name that has been shredded' do
    expect(described_class.new(**valid_attributes, name: Stweak::Domain::ValueMissing).name)
      .to eq(Stweak::Domain::ValueMissing)
  end

  it 'accepts an email that has been shredded' do
    expect(described_class.new(**valid_attributes, email: Stweak::Domain::ValueMissing).email)
      .to eq(Stweak::Domain::ValueMissing)
  end

  it 'serializes a shredded name as the marker, not a string' do
    serialized = described_class.new(**valid_attributes, name: Stweak::Domain::ValueMissing).to_h
    expect(serialized['name']).to be(Stweak::Domain::ValueMissing)
  end

  it 'serializes a shredded email as the marker, not a string' do
    serialized = described_class.new(**valid_attributes, email: Stweak::Domain::ValueMissing).to_h
    expect(serialized['email']).to be(Stweak::Domain::ValueMissing)
  end

  it 'rebuilds a shredded name as the marker, not a value object' do
    shredded = described_class.new(**valid_attributes, name: Stweak::Domain::ValueMissing)
    expect(described_class.from_h(shredded.to_h).name).to be(Stweak::Domain::ValueMissing)
  end

  it 'rebuilds a shredded email as the marker, not a value object' do
    shredded = described_class.new(**valid_attributes, email: Stweak::Domain::ValueMissing)
    expect(described_class.from_h(shredded.to_h).email).to be(Stweak::Domain::ValueMissing)
  end

  it 'rebuilds a present name as a DisplayName' do
    expect(described_class.from_h(event.to_h).name).to eq(make_display_name('Alice'))
  end

  it 'rebuilds a present email as an Email' do
    expect(described_class.from_h(event.to_h).email).to eq(make_email('alice@example.com'))
  end
end
