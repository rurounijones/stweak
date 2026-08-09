# typed: false
# frozen_string_literal: true

require_relative '../../../../lib/stweak/domain/security/password_hasher'
require_relative '../../../../lib/stweak/adapters/security/pbkdf2_password_hasher'
RSpec.describe Stweak::Domain::Security::PasswordHasher do
  it 'declares the digest method implementors must provide' do
    expect(described_class.instance_methods).to include(:digest)
  end

  it 'is implemented by the PBKDF2 hasher' do
    expect(Stweak::Adapters::Security::Pbkdf2PasswordHasher.ancestors)
      .to include(described_class)
  end
end
