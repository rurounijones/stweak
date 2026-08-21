# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/accounts/authenticate_account'
require_relative '../../../../lib/stweak/ports/projection_store'
require_relative '../../../../lib/stweak/domain/security/password_hasher'

RSpec.describe Stweak::Domain::Accounts::AuthenticateAccount do
  subject(:service) do
    described_class.new(projection_store: projection_store, password_hasher: password_hasher)
  end

  let(:projection_store) { instance_double(Stweak::Ports::ProjectionStore) }
  let(:password_hasher) { instance_double(Stweak::Domain::Security::PasswordHasher) }

  # The stored hash is a Symbol, not a String, so the coercion to a string
  # before verifying is exercised and pinned: a caller that dropped it would
  # hand the hasher the wrong type.
  let(:account) { { username: 'alice', password_hash: :'stored-digest', name: 'Alice' } }
  let(:other) { { username: 'bob', password_hash: 'other-digest', name: 'Bob' } }

  before do
    allow(projection_store).to receive(:read_all).with(table: :accounts).and_return([other, account])
  end

  it 'returns the matching account when the password verifies' do
    allow(password_hasher).to receive(:verify).with(password: 'pw', digest: 'stored-digest').and_return(true)

    expect(service.call(username: 'alice', password: 'pw')).to eq(account)
  end

  it 'returns nil when no account has the username' do
    allow(password_hasher).to receive(:verify)

    expect(service.call(username: 'nobody', password: 'pw')).to be_nil
  end

  it 'does not attempt to verify when no account has the username' do
    allow(password_hasher).to receive(:verify)

    service.call(username: 'nobody', password: 'pw')

    expect(password_hasher).not_to have_received(:verify)
  end

  it 'returns nil when the password does not verify against the found account' do
    allow(password_hasher).to receive(:verify).with(password: 'pw', digest: 'stored-digest').and_return(false)

    expect(service.call(username: 'alice', password: 'pw')).to be_nil
  end

  it 'verifies against the found account digest coerced to a string, not another account' do
    allow(password_hasher).to receive(:verify).and_return(true)

    service.call(username: 'alice', password: 'pw')

    expect(password_hasher).to have_received(:verify).with(password: 'pw', digest: 'stored-digest')
  end

  it 'skips a projected row that has no username rather than failing on it' do
    allow(projection_store).to receive(:read_all).with(table: :accounts).and_return([{ password_hash: 'x' }, account])
    allow(password_hasher).to receive(:verify).with(password: 'pw', digest: 'stored-digest').and_return(true)

    expect(service.call(username: 'alice', password: 'pw')).to eq(account)
  end
end
