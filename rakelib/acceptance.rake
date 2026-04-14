# frozen_string_literal: true

require 'fileutils'
require 'rake/testtask'
require_relative 'utils/container'

COMPOSE_FILE = 'test/acceptance/docker/docker-compose.yml'
SSH_KEY_PATH = 'test/acceptance/fixtures/keys/id_rsa'
SSL_EXPORT_DIR = 'test/acceptance/docker/ssl-export'

Rake::TestTask.new('acceptance:run') do |task|
  task.libs << 'test'
  task.test_files = FileList['test/acceptance/tests/**/*_test.rb']
  task.options = '--verbose'
  task.verbose = true
end

desc 'Run acceptance tests against SSH targets.'
task 'acceptance:ssh' do
  ENV['ACCEPTANCE_TRANSPORT'] = 'ssh'
  Rake::Task['acceptance:run'].invoke
end

namespace :acceptance do
  namespace :ssh do
    desc 'Start proxy and SSH target containers for acceptance tests.'
    task :up do
      unless File.exist?(SSH_KEY_PATH)
        FileUtils.mkdir_p(File.dirname(SSH_KEY_PATH))
        Shell.run(['ssh-keygen', '-t', 'rsa', '-b', '2048', '-f', SSH_KEY_PATH, '-N', '', '-q'])
        File.chmod(0600, SSH_KEY_PATH)
      end

      Container.compose(COMPOSE_FILE, 'up', '-d', '--build', '--wait')

      # Copy client certs out of the container for the test runner
      FileUtils.mkdir_p(SSL_EXPORT_DIR)
      %w[ca.pem client.pem client-key.pem].each do |cert|
        Shell.run(['docker', 'cp', "openbolt-proxy:/etc/foreman-proxy/ssl/#{cert}", "#{SSL_EXPORT_DIR}/#{cert}"])
      end
      puts 'Proxy is healthy and ready for acceptance tests.'.green
    end

    desc 'Stop containers and clean up generated keys and certs.'
    task :down do
      Container.compose(COMPOSE_FILE, 'down')
      FileUtils.rm_rf(File.dirname(SSH_KEY_PATH))
      FileUtils.rm_rf(SSL_EXPORT_DIR)
    end
  end
end
