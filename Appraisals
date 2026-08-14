# frozen_string_literal: true

# One appraisal per supported Rails version. `bundle exec appraisal install`
# regenerates gemfiles/ and their lockfiles.

# concurrent-ruby >= 1.3.5 dropped the implicit `require 'logger'` that
# Rails < 7.1 relies on.
CONCURRENT_RUBY_PIN = '< 1.3.5'

appraise 'rails-6.1' do
  gem 'activerecord', '~> 6.1.0'
  gem 'activesupport', '~> 6.1.0'
  gem 'concurrent-ruby', CONCURRENT_RUBY_PIN
end

appraise 'rails-7.0' do
  gem 'activerecord', '~> 7.0.0'
  gem 'activesupport', '~> 7.0.0'
  gem 'concurrent-ruby', CONCURRENT_RUBY_PIN
end

appraise 'rails-7.1' do
  gem 'activerecord', '~> 7.1.0'
  gem 'activesupport', '~> 7.1.0'
end

appraise 'rails-7.2' do
  gem 'activerecord', '~> 7.2.0'
  gem 'activesupport', '~> 7.2.0'
end

appraise 'rails-8.0' do
  gem 'activerecord', '~> 8.0.0'
  gem 'activesupport', '~> 8.0.0'
end

appraise 'rails-8.1' do
  gem 'activerecord', '~> 8.1.0'
  gem 'activesupport', '~> 8.1.0'
end
