# typed: false
# frozen_string_literal: true

require 'dotenv'
Dotenv.load

require_relative 'lib/wiring'
require_relative 'lib/web_admin'

WebAdmin::App.set(:reader, WebAdmin::Wiring.reader)
run WebAdmin::App
