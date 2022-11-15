# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('../spec/dummy/config/environment', __dir__)
require 'rspec/rails'

ActiveRecord::MigrationContext.new(File.expand_path('dummy/db/migrate', __dir__), ActiveRecord::SchemaMigration).migrate

ActiveRecord::Migration.check_pending! if ActiveRecord::Migration.respond_to?(:check_pending!)
