# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

# `require 'rails/dummy/tasks'` used to live here. It registered `rake dummy:app`,
# whose first step is FileUtils.rm_rf('spec/dummy') before regenerating the app
# from scratch. This dummy app is hand-maintained and checked in -- it has models,
# migrations and a database.yml the specs depend on -- so running that task
# destroyed the fixtures. Removed along with the rails-dummy dependency.

RSpec::Core::RakeTask.new(:spec)

task default: :spec
