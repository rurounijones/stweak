# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'stweak'
require_relative '../lib/web_admin'

# Test doubles for the web app, wrapped in a module so the spec file declares a
# single top-level constant and nothing leaks from an example group.
module Doubles
  # A stand-in event carrying just what the account view reads, including a
  # shredded (ValueMissing) field so the `display` helper's missing branch is
  # exercised.
  class FakeEvent
    attr_reader :type, :sequence, :occurred_at

    def initialize(type:, sequence:, occurred_at:, fields:)
      @type = type
      @sequence = sequence
      @occurred_at = occurred_at
      @fields = fields
    end

    def to_h = @fields
  end

  # A stand-in Reader, so the routes can be driven without any stores.
  class FakeReader
    attr_reader :accounts

    def initialize(accounts:, events: [])
      @accounts = accounts
      @events = events
    end

    def account(id) = accounts.find { |row| row[:account_id] == id }
    def events(_id) = @events
  end
end

RSpec.describe WebAdmin::App do
  include Rack::Test::Methods

  let(:app) { described_class }

  let(:account) do
    {
      account_id: 'abc', username: 'ada', name: 'Ada',
      email: Stweak::Domain::ValueMissing, created_at: '2026-01-01T00:00:00Z'
    }
  end

  let(:event) do
    Doubles::FakeEvent.new(
      type: 'AccountCreated', sequence: 1, occurred_at: Time.utc(2026, 1, 1),
      fields: { 'type' => 'AccountCreated', 'version' => 1, 'sequence' => 1,
                'username' => 'ada', 'name' => 'Ada', 'email' => Stweak::Domain::ValueMissing }
    )
  end

  before { app.set(:reader, Doubles::FakeReader.new(accounts: [account], events: [event])) }

  it 'lists accounts on the home page' do
    get '/'

    aggregate_failures do
      expect(last_response).to be_ok
      expect(last_response.body).to include('Accounts').and include('ada')
    end
  end

  it 'shows a blank slate when there are no accounts' do
    app.set(:reader, Doubles::FakeReader.new(accounts: []))

    get '/'

    expect(last_response.body).to include('No accounts to show')
  end

  it 'shows an account with its data and events, dashing shredded fields' do
    get '/accounts/abc'

    aggregate_failures do
      expect(last_response).to be_ok
      expect(last_response.body).to include('Ada').and include('AccountCreated').and include('—')
    end
  end

  it 'returns 404 for an unknown account' do
    get '/accounts/nope'

    aggregate_failures do
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Not found')
    end
  end
end
