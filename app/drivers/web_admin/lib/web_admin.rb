# typed: false
# frozen_string_literal: true

require 'sinatra/base'
require 'stweak'

module WebAdmin
  # The read-only web app: three routes over a Reader, which is injected as a
  # setting so the same routes serve the real stores in production and an
  # in-memory Reader under test. The file is `typed: false` because Sinatra's
  # class-level DSL (`get`, `erb`) does not type cleanly, matching the choice
  # the spec files make.
  class App < Sinatra::Base
    set :views, File.expand_path('../views', __dir__)
    # A read-only demo served locally; Sinatra 4's host allow-list only gets in
    # the way here, so it is disabled (an empty permitted list allows any host).
    set :host_authorization, permitted_hosts: []

    # View helpers, in a module rather than a `helpers` block so the method is
    # defined normally rather than inside a block.
    module Helpers
      # Render a projected value, showing shredded personal data as a dash
      # rather than the ValueMissing marker.
      def display(value)
        value == Stweak::Domain::ValueMissing ? '—' : value.to_s
      end
    end
    helpers Helpers

    # The account list.
    get '/' do
      @accounts = settings.reader.accounts
      erb :index
    end

    # One account: its projected data, then its events.
    get '/accounts/:id' do
      @account = settings.reader.account(params[:id])
      if @account
        @events = settings.reader.events(params[:id])
        erb :account
      else
        status 404
        erb :not_found
      end
    end
  end
end
