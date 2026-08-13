# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in recorder.gemspec
gemspec

# Development pins, removable with the Rails upgrade.

# concurrent-ruby >= 1.3.5 has no implicit `require 'logger'`; Rails < 7.1 needs it.
gem 'concurrent-ruby', '< 1.3.5'

# rubocop-factory_bot >= 2.24 needs a newer rubocop than standard 1.29 allows.
gem 'rubocop-factory_bot', '~> 2.23.0'
