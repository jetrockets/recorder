require 'spec_helper'
require File.expand_path('../../spec/dummy/config/environment', __FILE__)
require 'rspec/rails'

ActiveRecord::Migration.check_pending! if ActiveRecord::Migration.respond_to?(:check_pending!)
