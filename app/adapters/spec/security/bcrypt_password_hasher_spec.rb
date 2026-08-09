# typed: false
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../security/bcrypt_password_hasher'

RSpec.describe App::Adapters::BcryptPasswordHasher do
  subject(:hasher) { described_class.new }

  it 'produces a bcrypt digest' do
    expect(hasher.digest(password: 'hunter2')).to start_with('$2')
  end

  it 'does not store the raw password' do
    expect(hasher.digest(password: 'hunter2')).not_to eq('hunter2')
  end

  it 'produces a different digest for a different password' do
    expect(hasher.digest(password: 'hunter2')).not_to eq(hasher.digest(password: 'password'))
  end
end
