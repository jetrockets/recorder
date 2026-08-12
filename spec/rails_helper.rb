# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('../spec/dummy/config/environment', __dir__)
require 'rspec/rails'

ActiveRecord::MigrationContext.new(File.expand_path('dummy/db/migrate', __dir__), ActiveRecord::SchemaMigration).migrate

ActiveRecord::Migration.check_pending! if ActiveRecord::Migration.respond_to?(:check_pending!)

RSpec.configure do |config|
  # Recorder holds state in three places that outlive an example: database rows,
  # the Config singleton, and the RequestStore that Store memoises. A leaked
  # `recorder_disabled!` makes later examples record nothing and pass anyway.

  # RailsExampleGroup is included explicitly: rspec-rails' global FixtureSupport
  # include is deprecated (rspec/rspec-rails#1355), and without one of the two
  # these groups get no transaction, none being in Rails-typed directories.
  config.include RSpec::Rails::RailsExampleGroup
  config.use_transactional_fixtures = true

  config.before do
    RequestStore.clear!
    Recorder::Config.instance.reset
    Recorder.instance_variable_set(:@store, nil) # Store memoises the wrapper
  end
end
