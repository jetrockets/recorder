# frozen_string_literal: true

# Started before anything under lib/ loads, or those files go uncounted.
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'recorder'

ENV['RAILS_ENV'] = 'test'

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
end
