# typed: false
# frozen_string_literal: true

require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative 'lib/wiring'
require_relative 'lib/web_admin'

WebAdmin::App.set(:reader, WebAdmin::Wiring.reader)
run WebAdmin::App
