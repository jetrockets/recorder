# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'recorder'

ENV['RAILS_ENV'] = 'test'

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
end
