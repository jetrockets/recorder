# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('../spec/dummy/config/environment', __dir__)
require 'rspec/rails'

ActiveRecord::Migrator.migrate File.expand_path('dummy/db/migrate', __dir__)

ActiveRecord::Migration.check_pending! if ActiveRecord::Migration.respond_to?(:check_pending!)

# RSpec.configure do |config|
#   # config.include FactoryGirl::Syntax::Methods

#   config.before(:each) do
#     DatabaseCleaner.strategy = :transaction
#   end
# end
