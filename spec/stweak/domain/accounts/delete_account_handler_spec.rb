# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/delete_account_handler'
require_relative '../../../../lib/stweak/domain/accounts/delete_account'
require_relative '../../../../lib/stweak/domain/accounts/account'
require_relative '../../../../lib/stweak/domain/accounts/account_created'
require_relative '../../../../lib/stweak/domain/checkpoint'
require_relative '../../../../lib/stweak/ports/event_store'
require_relative '../../../../lib/stweak/ports/checkpoint_store'

# A run of AccountCreated events at sequences 1..count on one stream, so an
# account can be replayed to any length without an event store behind it.
def delete_created_events(account_id, count)
  (1..count).map do |sequence|
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: account_id, sequence: sequence, occurred_at: Time.utc(2026, 1, 2, 3, 4, 5), account_id: account_id,
      username: Stweak::Domain::Accounts::Username.new(value: "user-#{sequence}"), password_hash: 'hash',
      name: Stweak::Domain::Accounts::DisplayName.new(value: "Name #{sequence}"),
      email: Stweak::Domain::Accounts::Email.new(value: "user#{sequence}@example.com")
    )
  end
end

# A checkpoint of a created account at version 100, for the checkpoint load path.
def delete_created_checkpoint
  Stweak::Domain::Checkpoint.new(
    state: { 'created' => true, 'disabled' => false, 'deleted' => false, 'username' => 'alice',
             'password_hash' => 'hash', 'name' => 'Alice', 'email' => 'alice@example.com' },
    version: 100
  )
end

RSpec.describe Stweak::Domain::Accounts::DeleteAccountHandler do
  subject(:handler) do
    described_class.new(event_store: event_store, checkpoint_store: checkpoint_store)
  end

  let(:account_id) { Stweak::Domain::Accounts::AccountId.new(value: '00000000-0000-4000-8000-000000000001') }
  let(:event_store) { instance_double(Stweak::Ports::EventStore) }
  let(:checkpoint_store) { instance_double(Stweak::Ports::CheckpointStore) }
  let(:command) { Stweak::Domain::Accounts::DeleteAccount.new(account_id: account_id) }

  before do
    allow(checkpoint_store).to receive(:get).and_return(nil)
    allow(checkpoint_store).to receive(:put)
    allow(event_store).to receive(:read_stream).and_return(delete_created_events(account_id, 1))
    allow(event_store).to receive(:append)
  end

  it 'returns the deleted account' do
    expect(handler.handle(command).deleted).to be(true)
  end

  it 'appends an AccountDeleted event' do
    handler.handle(command)
    expect(event_store).to have_received(:append)
      .with(hash_including(events: [an_instance_of(Stweak::Domain::Accounts::AccountDeleted)]))
  end

  it 'appends on the account stream at the expected version' do
    handler.handle(command)
    expect(event_store).to have_received(:append)
      .with(hash_including(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id, expected_version: 1))
  end

  it 'loads any checkpoint for the account' do
    handler.handle(command)
    expect(checkpoint_store).to have_received(:get)
      .with(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id)
  end

  it 'reads the whole stream when no checkpoint is stored' do
    handler.handle(command)
    expect(event_store).to have_received(:read_stream)
      .with(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id, after: 0)
  end

  it 'reads only the tail after the checkpoint version' do
    allow(checkpoint_store).to receive(:get).and_return(delete_created_checkpoint)
    handler.handle(command)
    expect(event_store).to have_received(:read_stream)
      .with(owner_type: Stweak::Domain::Accounts::Account, stream_id: account_id, after: 100)
  end

  it 'restores account state from the checkpoint when the tail is empty' do
    allow(checkpoint_store).to receive(:get).and_return(delete_created_checkpoint)
    allow(event_store).to receive(:read_stream).and_return([])
    expect(handler.handle(command).deleted).to be(true)
  end

  it 'writes no checkpoint before a hundred events' do
    handler.handle(command)
    expect(checkpoint_store).not_to have_received(:put)
  end

  it 'persists the checkpoint at a boundary' do
    allow(event_store).to receive(:read_stream).and_return(delete_created_events(account_id, 99))
    handler.handle(command)
    expect(checkpoint_store).to have_received(:put)
      .with(hash_including(owner_type: Stweak::Domain::Accounts::Account, owner_id: account_id,
                           checkpoint: an_instance_of(Stweak::Domain::Checkpoint)))
  end

  it 'surfaces a concurrent append as AccountAlreadyDeleted' do
    allow(event_store).to receive(:append).and_raise(Stweak::Ports::ConcurrencyError)
    expect { handler.handle(command) }.to raise_error(Stweak::Domain::Accounts::AccountAlreadyDeleted)
  end
end
