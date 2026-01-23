# frozen_string_literal: true

source 'https://rubygems.org'
gemspec

group :rubocop do
  gem 'rubocop', '~> 1.28.0'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
end

group :test do
  gem 'ci_reporter_test_unit'
  gem 'mocha', '~> 2'
  gem 'rack-test'
  gem 'rake', '~> 13'
  gem 'smart_proxy', github: 'theforeman/smart-proxy', ref: ENV.fetch('SMART_PROXY_BRANCH', 'develop')
  gem 'test-unit', '~> 3'
  gem 'webmock', '~> 3'
end

group :release, optional: true do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.16.4', require: false
end
