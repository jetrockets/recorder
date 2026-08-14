# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'recorder/version'

Gem::Specification.new do |spec|
  spec.name = 'recorder'
  spec.version = Recorder::VERSION
  spec.authors = ['Igor Alexandrov']
  spec.email = ['igor.alexandrov@jetrockets.com']

  spec.summary = 'Rails model auditor'
  spec.description = 'Recorder tracks changes of your Rails models'
  spec.homepage = 'https://github.com/jetrockets/recorder'
  spec.license = 'MIT'

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  # Only what a host app loads. Repo scaffolding — CI config, Rakefile, bin/,
  # dotfiles — is development-only and stays out of the released gem.
  spec.files = Dir['lib/**/*', 'CHANGELOG.md', 'LICENSE.txt', 'README.md'].select { |f| File.file?(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.0'

  spec.add_dependency 'activerecord', '>= 6.1', '< 9'
  spec.add_dependency 'activesupport', '>= 6.1', '< 9'
  spec.add_dependency 'request_store', '>= 1.0'

  spec.add_development_dependency 'appraisal', '~> 2.5'
  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'generator_spec', '~> 0.9'
  spec.add_development_dependency 'jetrockets-standard'
  # Revisions are stored in `jsonb` and `inet` columns; the dummy app is PostgreSQL.
  # Host apps supply their own adapter.
  spec.add_development_dependency 'pg', '>= 1.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec-rails', '>= 5.0'
end
