# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('../spec/dummy/config/environment', __dir__)
require 'rspec/rails'

ActiveRecord::MigrationContext.new(File.expand_path('dummy/db/migrate', __dir__), ActiveRecord::SchemaMigration).migrate

ActiveRecord::Migration.check_pending! if ActiveRecord::Migration.respond_to?(:check_pending!)

RSpec.configure do |config|
  # Recorder keeps state in three places that all outlive a single example, and
  # every one of them leaked before this block existed: rows stayed in the
  # database, Config is a Singleton, and Store memoises a RequestStore that is
  # never cleared outside a real request cycle.
  #
  # The store leak is the dangerous one. A stray `recorder_disabled!` silently
  # survives into later examples, which then record nothing and pass anyway --
  # exactly the failure mode that lets a broken observer look healthy. See
  # spec/isolation_spec.rb, which fails if any of this is removed.

  # Wraps each example in a transaction that is rolled back afterwards.
  #
  # RailsExampleGroup is included explicitly rather than relying on rspec-rails'
  # global FixtureSupport include, which is deprecated (rspec/rspec-rails#1355)
  # and due for removal in rspec-rails 7. Without one of the two, plain
  # RSpec.describe groups get no transaction and this setting does nothing --
  # the specs here are not in Rails-typed directories, so nothing infers it.
  config.include RSpec::Rails::RailsExampleGroup
  config.use_transactional_fixtures = true

  config.before do
    RequestStore.clear!
    Recorder::Config.instance.reset
    # Store memoises the RequestStore wrapper, so drop the instance too.
    Recorder.instance_variable_set(:@store, nil)
  end
end
