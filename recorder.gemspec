# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'recorder/version'

Gem::Specification.new do |spec|
  spec.name = 'recorder'
  spec.version = Recorder::VERSION::STRING
  spec.authors = ['Igor Alexandrov']
  spec.email = ['igor.alexandrov@jetrockets.ru']

  spec.summary = 'Rails model auditor'
  spec.description = 'Recorder tracks changes of your Rails models'
  spec.homepage = 'https://github.com/jetrockets/recorder'
  spec.license = 'MIT'

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 4.0'
  spec.add_dependency 'activesupport', '>= 4.0'
  spec.add_dependency 'pg'
  spec.add_dependency 'request_store'

  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'generator_spec'
  spec.add_development_dependency 'jetrockets-standard'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec-rails', '~> 3.5'
  spec.add_development_dependency 'timecop', '~> 0.8.1'
  spec.add_development_dependency 'yard'
end
