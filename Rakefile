# frozen_string_literal: true

require 'ci/reporter/rake/test_unit'
require 'fileutils'
require 'rake'
require 'rake/testtask'
require 'rubocop/rake_task'

RuboCop::RakeTask.new

desc 'Default: run unit tests.'
task :default => :test

desc 'Run unit tests.'
Rake::TestTask.new(:test) do |t|
  t.libs << '.'
  t.libs << 'lib'
  t.libs << 'test'
  t.test_files = FileList['test/unit/**/*_test.rb']
  t.options = '--verbose'
  t.verbose = true
end

ACCEPTANCE_TEST_FILES = FileList['test/acceptance/tests/*_test.rb']
DOCKER_COMPOSE = 'test/acceptance/docker/docker-compose.yml'
SSH_KEY_PATH = 'test/acceptance/fixtures/keys/id_rsa'
SSL_EXPORT_DIR = 'test/acceptance/docker/ssl-export'

Rake::TestTask.new('test:acceptance') do |task|
  task.libs << 'test'
  task.test_files = ACCEPTANCE_TEST_FILES
  task.options = '--verbose'
  task.verbose = true
end

desc 'Run acceptance tests against SSH targets.'
task 'test:acceptance:ssh' do
  ENV['ACCEPTANCE_TRANSPORT'] = 'ssh'
  Rake::Task['test:acceptance'].invoke
end

namespace :test do
  namespace :acceptance do
    namespace :ssh do
      desc 'Start proxy and SSH target containers for acceptance tests.'
      task :up do
        unless File.exist?(SSH_KEY_PATH)
          FileUtils.mkdir_p(File.dirname(SSH_KEY_PATH))
          sh 'ssh-keygen', '-t', 'rsa', '-b', '2048', '-f', SSH_KEY_PATH, '-N', '', '-q'
          File.chmod(0600, SSH_KEY_PATH)
        end

        sh "docker compose -f #{DOCKER_COMPOSE} up -d --build"

        # Wait for the proxy to be healthy (healthcheck polls /openbolt/tasks)
        puts 'Waiting for proxy to become healthy...'
        ready = false
        60.times do
          output = `docker compose -f #{DOCKER_COMPOSE} ps proxy --format json 2>&1`
          abort "docker compose failed: #{output.strip}" unless $?.success?
          if output.include?('"healthy"')
            ready = true
            break
          end
          sleep 2
        end
        abort "Proxy did not become healthy within 120s. Check: docker compose -f #{DOCKER_COMPOSE} logs proxy" unless ready

        # Copy client certs out of the container for the test runner
        FileUtils.mkdir_p(SSL_EXPORT_DIR)
        %w[ca.pem client.pem client-key.pem].each do |cert|
          sh "docker cp openbolt-proxy:/etc/foreman-proxy/ssl/#{cert} #{SSL_EXPORT_DIR}/#{cert}"
        end
        puts 'Proxy is healthy and ready for acceptance tests.'
      end

      desc 'Stop containers and clean up generated keys and certs.'
      task :down do
        system("docker compose -f #{DOCKER_COMPOSE} down")
        rm_rf File.dirname(SSH_KEY_PATH)
        rm_rf SSL_EXPORT_DIR
      end
    end
  end
end

begin
  require 'rubygems'
  require 'github_changelog_generator/task'

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.exclude_labels = %w[duplicate question invalid wontfix wont-fix skip-changelog github_actions]
    config.user = 'overlookinfra'
    config.project = 'smart_proxy_openbolt'
    gem_version = Gem::Specification.load("#{config.project}.gemspec").version
    config.future_release = gem_version
  end
rescue LoadError
  task :changelog do
    abort("Run `bundle install --with release` to install the `github_changelog_generator` gem.")
  end
end
