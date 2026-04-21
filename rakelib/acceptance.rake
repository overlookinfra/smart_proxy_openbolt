# frozen_string_literal: true

require 'fileutils'
require 'rake/testtask'
require_relative 'utils/container'

SSH_COMPOSE_FILE = 'test/acceptance/ssh/docker/docker-compose.yml'
CHORIA_COMPOSE_FILE = 'test/acceptance/choria/docker/docker-compose.yml'
CHORIA_DOCKER_DIR = 'test/acceptance/choria/docker'
CHORIA_FIXTURES_DIR = 'test/acceptance/choria/fixtures'
SSH_KEY_PATH = 'test/acceptance/ssh/fixtures/keys/id_rsa'
SSL_EXPORT_DIR = 'test/acceptance/ssl-export'

CHORIA_PROXY_BASE = 'openbolt-choria-proxy-base'
CHORIA_PROXY_PREPARED = 'openbolt-choria-proxy-prepared'
CHORIA_TARGET_BASE = 'openbolt-choria-target-base'
CHORIA_TARGET1_PREPARED = 'openbolt-choria-target1-prepared'
CHORIA_TARGET2_PREPARED = 'openbolt-choria-target2-prepared'
CHORIA_SETUP_NETWORK = 'choria-setup-network'

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

desc 'Run acceptance tests against Choria targets.'
task 'acceptance:choria' do
  ENV['ACCEPTANCE_TRANSPORT'] = 'choria'
  ENV['PROXY_PORT'] = '8444'
  Rake::Task['acceptance:run'].invoke
end

def choria_volume_args
  fixtures = File.expand_path(CHORIA_FIXTURES_DIR)
  args = [
    '-v', "#{fixtures}/puppet/Puppetfile:/etc/puppetlabs/code/environments/production/Puppetfile:ro",
    '-v', "#{fixtures}/puppet/hiera.yaml:/etc/puppetlabs/code/environments/production/hiera.yaml:ro",
    '-v', "#{fixtures}/puppet/data:/etc/puppetlabs/code/environments/production/data:ro",
    '-v', "#{fixtures}/puppet/manifests:/etc/puppetlabs/code/environments/production/manifests:ro",
  ]
  rpms_dir = File.join(fixtures, 'rpms')
  args.push('-v', "#{rpms_dir}:/opt/rpms:ro") if Dir.glob(File.join(rpms_dir, '*.rpm')).any?
  args
end

def wait_until(description, timeout: 120)
  deadline = Time.now + timeout
  loop do
    return if yield
    if Time.now > deadline
      abort "ERROR: Timed out waiting for #{description} (#{timeout}s)".red
    end
    sleep 5
  end
end

def build_choria_base_images
  unless Container.image_exists?(CHORIA_PROXY_BASE)
    puts '==> Building Choria proxy base image...'.magenta
    Container.build_image(
      tag: CHORIA_PROXY_BASE,
      dockerfile: File.join(CHORIA_DOCKER_DIR, 'proxy', 'Dockerfile'),
      context: CHORIA_DOCKER_DIR,
      platform: 'linux/amd64'
    )
  end

  unless Container.image_exists?(CHORIA_TARGET_BASE)
    puts '==> Building Choria target base image...'.magenta
    Container.build_image(
      tag: CHORIA_TARGET_BASE,
      dockerfile: File.join(CHORIA_DOCKER_DIR, 'target', 'Dockerfile'),
      context: CHORIA_DOCKER_DIR,
      platform: 'linux/amd64'
    )
  end
end

def prepare_choria_images
  return if Container.image_exists?(CHORIA_PROXY_PREPARED) &&
            Container.image_exists?(CHORIA_TARGET1_PREPARED) &&
            Container.image_exists?(CHORIA_TARGET2_PREPARED)

  build_choria_base_images

  Shell.run(['docker', 'network', 'create', CHORIA_SETUP_NETWORK],
            allowed_exit_codes: [0, 1])

  proxy = Container.new(name: 'choria-proxy-setup', image: CHORIA_PROXY_BASE)
  target1 = Container.new(name: 'choria-target1-setup', image: CHORIA_TARGET_BASE)
  target2 = Container.new(name: 'choria-target2-setup', image: CHORIA_TARGET_BASE)

  begin
    [proxy, target1, target2].each do |container|
      Shell.capture(['docker', 'rm', '-f', container.name],
                    print_command: false, allowed_exit_codes: [0, 1])
    end

    # Start proxy with setup script
    puts '==> Running Choria proxy setup...'.magenta
    Shell.run([
      'docker', 'run', '-d',
      '--name', proxy.name,
      '--hostname', 'choria-proxy',
      '--platform', 'linux/amd64',
      '--network', CHORIA_SETUP_NETWORK,
      *choria_volume_args,
      CHORIA_PROXY_BASE, '/setup.sh'
    ])

    proxy_logs = spawn('docker', 'logs', '-f', proxy.name)

    wait_until('OpenVox Server', timeout: 600) do
      Shell.capture(
        ['docker', 'exec', proxy.name, 'curl', '-sfk', 'https://localhost:8140/status/v1/services'],
        print_command: false, allowed_exit_codes: [0, 7, 22, 28]
      ).exitcode == 0
    end

    wait_until('NATS broker', timeout: 60) do
      Shell.capture(
        ['docker', 'exec', proxy.name, 'bash', '-c', 'echo > /dev/tcp/localhost/4222'],
        print_command: false, allowed_exit_codes: [0, 1]
      ).exitcode == 0
    end

    Process.kill('TERM', proxy_logs) rescue nil
    Process.wait(proxy_logs) rescue nil

    # Start both targets with setup script
    puts '==> Running Choria target setup...'.magenta
    Shell.run([
      'docker', 'run', '-d',
      '--name', target1.name,
      '--hostname', 'choria-target1',
      '--platform', 'linux/amd64',
      '--network', CHORIA_SETUP_NETWORK,
      CHORIA_TARGET_BASE, '/setup.sh'
    ])
    Shell.run([
      'docker', 'run', '-d',
      '--name', target2.name,
      '--hostname', 'choria-target2',
      '--platform', 'linux/amd64',
      '--network', CHORIA_SETUP_NETWORK,
      CHORIA_TARGET_BASE, '/setup.sh'
    ])

    target1_logs = spawn('docker', 'logs', '-f', target1.name)
    target2_logs = spawn('docker', 'logs', '-f', target2.name)

    wait_until('target1 choria-server', timeout: 300) do
      Shell.capture(
        ['docker', 'exec', target1.name, 'pgrep', '-f', 'choria server'],
        print_command: false, allowed_exit_codes: [0, 1]
      ).exitcode == 0
    end
    wait_until('target2 choria-server', timeout: 300) do
      Shell.capture(
        ['docker', 'exec', target2.name, 'pgrep', '-f', 'choria server'],
        print_command: false, allowed_exit_codes: [0, 1]
      ).exitcode == 0
    end

    [target1_logs, target2_logs].each do |pid|
      Process.kill('TERM', pid) rescue nil
      Process.wait(pid) rescue nil
    end

    # Verify Choria connectivity
    puts '==> Verifying Choria connectivity...'.magenta
    proxy.exec('choria ping')

    # Stop and commit all three
    puts '==> Committing prepared images...'.magenta
    [target1, target2, proxy].each(&:stop)
    proxy.commit(CHORIA_PROXY_PREPARED)
    target1.commit(CHORIA_TARGET1_PREPARED)
    target2.commit(CHORIA_TARGET2_PREPARED)
    puts 'Choria images prepared.'.green
  ensure
    [proxy, target1, target2].each(&:teardown)
    Shell.run(['docker', 'network', 'rm', CHORIA_SETUP_NETWORK],
              allowed_exit_codes: [0, 1])
  end
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

      Container.compose(SSH_COMPOSE_FILE, 'up', '-d', '--build', '--wait')

      FileUtils.mkdir_p(SSL_EXPORT_DIR)
      %w[ca.pem client.pem client-key.pem].each do |cert|
        Shell.run(['docker', 'cp', "openbolt-proxy:/etc/foreman-proxy/ssl/#{cert}", "#{SSL_EXPORT_DIR}/#{cert}"])
      end
      puts 'Proxy is healthy and ready for acceptance tests.'.green
    end

    desc 'Stop containers and clean up generated keys and certs.'
    task :down do
      Container.compose(SSH_COMPOSE_FILE, 'down')
      FileUtils.rm_rf(File.dirname(SSH_KEY_PATH))
      FileUtils.rm_rf(SSL_EXPORT_DIR)
    end
  end

  namespace :choria do
    desc 'Start Choria proxy and target containers for acceptance tests.'
    task :up do
      prepare_choria_images

      Container.compose(CHORIA_COMPOSE_FILE, 'up', '-d', '--wait')

      puppet_ssl = '/etc/puppetlabs/puppet/ssl'
      FileUtils.mkdir_p(SSL_EXPORT_DIR)
      Shell.run(['docker', 'cp', "openbolt-choria-proxy:#{puppet_ssl}/certs/ca.pem", "#{SSL_EXPORT_DIR}/ca.pem"])
      Shell.run(['docker', 'cp', "openbolt-choria-proxy:#{puppet_ssl}/certs/acceptance-test-client.pem", "#{SSL_EXPORT_DIR}/client.pem"])
      Shell.run(['docker', 'cp', "openbolt-choria-proxy:#{puppet_ssl}/private_keys/acceptance-test-client.pem", "#{SSL_EXPORT_DIR}/client-key.pem"])
      puts 'Choria infrastructure is healthy and ready for acceptance tests.'.green
    end

    desc 'Stop Choria containers and clean up.'
    task :down do
      Container.compose(CHORIA_COMPOSE_FILE, 'down')
      FileUtils.rm_rf(SSL_EXPORT_DIR)
    end
  end

  desc 'Stop all containers and remove all data and images (full reset).'
  task :clean do
    Container.compose(SSH_COMPOSE_FILE, 'down', '-v', '--rmi', 'all')
    Container.compose(CHORIA_COMPOSE_FILE, 'down', '-v', '--rmi', 'all')
    [CHORIA_PROXY_BASE, CHORIA_PROXY_PREPARED, CHORIA_TARGET_BASE,
     CHORIA_TARGET1_PREPARED, CHORIA_TARGET2_PREPARED].each do |repo|
      result = Shell.capture(['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}', repo],
                             print_command: false)
      result.output.each_line do |line|
        image_ref = line.strip
        next if image_ref.empty?
        Shell.run(['docker', 'rmi', image_ref], allowed_exit_codes: [0, 1])
      end
    end
    FileUtils.rm_rf(File.dirname(SSH_KEY_PATH))
    FileUtils.rm_rf(SSL_EXPORT_DIR)
  end
end
