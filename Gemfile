# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in recorder.gemspec
gemspec

# Temporary pins. Both exist only because the gem is still on Rails 6.1 and on
# the RuboCop stack that jetrockets-standard 1.29 pulls in. Drop them together
# with the Rails upgrade -- they are development constraints, so they belong
# here rather than in the gemspec, where they would be inflicted on consumers.

# concurrent-ruby >= 1.3.5 dropped its implicit `require 'logger'`, which
# Rails < 7.1 depends on. Without this pin every spec file fails to load with
# NameError: uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger
gem 'concurrent-ruby', '< 1.3.5'

# jetrockets-standard pins rubocop-rspec to ~> 2.22.0, which lets
# rubocop-factory_bot float up to 2.26.0. That release declares a `contextual`
# AutoCorrect value that the rubocop 1.52.1 pinned by standard 1.29 cannot
# parse, so `rubocop` aborts before linting anything.
gem 'rubocop-factory_bot', '~> 2.23.0'
