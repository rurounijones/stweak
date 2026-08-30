# typed: false
# frozen_string_literal: true

require_relative 'generators'

# Generators for the domain's own types, built from the domain-independent
# generators in this directory. Specs include this module to get them as
# methods.
module DomainPropertyGenerators
  include PropertyGenerators

  # A valid AccountCreated event.
  def account_created_event
    tuple(
      uuid, positive_integer, time, uuid,
      nonempty_string, nonempty_string, nonempty_string, nonempty_string
    ).map { |fields| build_account_created_event(fields) }
  end

  # A valid CreateAccount command.
  def create_account_command
    tuple(uuid, nonempty_string, nonempty_string, nonempty_string, nonempty_string)
      .map do |(account_id, username, password, name, email)|
        Stweak::Domain::Accounts::CreateAccount.new(
          account_id: Stweak::Domain::Accounts::AccountId.new(value: account_id),
          username: Stweak::Domain::Accounts::Username.new(value: username), password: password,
          name: Stweak::Domain::Accounts::DisplayName.new(value: name),
          email: Stweak::Domain::Accounts::Email.new(value: email)
        )
      end
  end

  # Build an AccountCreated from raw tuple fields, wrapping each in its value
  # object. Extracted so the generator above stays within method-length limits.
  def build_account_created_event(fields)
    stream_id, sequence, occurred_at, account_id, username, password_hash, name, email = fields
    Stweak::Domain::Accounts::AccountCreated.new(
      stream_id: Stweak::Domain::Accounts::AccountId.new(value: stream_id), sequence: sequence,
      occurred_at: occurred_at, account_id: Stweak::Domain::Accounts::AccountId.new(value: account_id),
      username: Stweak::Domain::Accounts::Username.new(value: username), password_hash: password_hash,
      name: Stweak::Domain::Accounts::DisplayName.new(value: name),
      email: Stweak::Domain::Accounts::Email.new(value: email)
    )
  end

  # A list of events on one stream, with consecutive sequences starting at one.
  def event_sequence
    tuple(uuid, choose(1..10)).bind do |(stream_id, count)|
      array(account_created_event, min: count, max: count).map do |events|
        events.each_with_index.map do |event, index|
          event.with('stream_id' => stream_id, 'account_id' => stream_id, 'sequence' => index + 1)
        end
      end
    end
  end
end
