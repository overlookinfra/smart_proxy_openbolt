# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'utils/shell'
require_relative 'utils/container'

FOREMAN_PACKAGING_REPO = ENV.fetch('FOREMAN_PACKAGING_REPO', 'https://github.com/theforeman/foreman-packaging.git')
GEMSPEC = 'smart_proxy_openbolt.gemspec'
GEM_FILENAME = "smart_proxy_openbolt-#{Gem::Specification.load(GEMSPEC).version}.gem".freeze

def foreman_packaging_branch(foreman_version)
  foreman_version == 'nightly' ? 'develop' : foreman_version
end

def foreman_packaging_path(foreman_version, branch_prefix: 'rpm')
  packaging_version = foreman_packaging_branch(foreman_version)
  @foreman_packaging_paths ||= {}
  key = "#{branch_prefix}-#{packaging_version}"
  @foreman_packaging_paths[key] ||= begin
    branch = "#{branch_prefix}/#{packaging_version}"
    dir = File.join(Dir.tmpdir, "foreman-packaging-#{key}")
    if File.directory?(dir)
      puts "Updating foreman-packaging (#{branch})...".magenta
      Shell.run(['git', '-C', dir, 'fetch', '--depth', '1', 'origin', branch])
      Shell.run(['git', '-C', dir, 'reset', '--hard', 'FETCH_HEAD'])
    else
      puts "Cloning foreman-packaging (#{branch})...".magenta
      Shell.run(['git', 'clone', '--depth', '1', '--branch', branch,
                 FOREMAN_PACKAGING_REPO, dir])
    end
    dir
  end
end

def build_rpm_builder_image(foreman_version)
  image_name = "smart-proxy-openbolt-rpm-builder:#{foreman_version}"
  return image_name if Container.image_exists?(image_name)

  puts "Building RPM builder image for Foreman #{foreman_version}...".magenta
  Container.build_image(
    tag: 'foreman-packaging-base',
    dockerfile: File.join(foreman_packaging_path(foreman_version), 'Containerfile'),
    platform: 'linux/amd64'
  )

  Container.prepare_image(target_tag: image_name,
    base_image: 'foreman-packaging-base', setup_name: 'rpm-builder-setup') do |runner|
    runner.run(<<~BASH, platform: 'linux/amd64')
      set -e
      dnf install -y glibc-langpack-en
      dnf install -y https://yum.theforeman.org/releases/#{foreman_version}/el9/x86_64/foreman-release.rpm
      dnf install -y rubygems-devel foreman-plugin foreman-assets rubygem-foreman-tasks
      rpmdev-setuptree
    BASH
  end
end

def build_deb_builder_image(foreman_version)
  image_name = "smart-proxy-openbolt-deb-builder:#{foreman_version}"
  return image_name if Container.image_exists?(image_name)

  puts "Building DEB builder image for Foreman #{foreman_version}...".magenta

  Container.prepare_image(target_tag: image_name,
    base_image: 'debian:bookworm', setup_name: 'deb-builder-setup') do |runner|
    runner.run(<<~BASH, platform: 'linux/amd64')
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y wget gnupg ca-certificates
      echo "deb http://deb.theforeman.org/ bookworm #{foreman_version}" \
        > /etc/apt/sources.list.d/foreman.list
      echo "deb http://deb.theforeman.org/ plugins #{foreman_version}" \
        >> /etc/apt/sources.list.d/foreman.list
      wget -qO- https://deb.theforeman.org/foreman.asc | gpg --dearmor \
        > /etc/apt/trusted.gpg.d/foreman.gpg
      apt-get update
      apt-get install -y gem2deb debhelper rake ruby ruby-dev ruby-concurrent
    BASH
  end
end

namespace :build do
  desc 'Build the gem'
  task :gem do
    FileUtils.mkdir_p('pkg')
    FileUtils.rm_f(Dir.glob('pkg/smart_proxy_openbolt-*.gem'))
    Shell.run(['gem', 'build', GEMSPEC])
    FileUtils.mv(GEM_FILENAME, 'pkg/')
  end

  desc 'Build RPM using foreman-packaging spec and container'
  task rpm: :gem do
    FileUtils.rm_f(Dir.glob('pkg/rubygem-smart_proxy_openbolt-*.rpm'))

    Container.run_once(
      image: build_rpm_builder_image(FOREMAN_VERSION),
      cmd: <<~BASH,
        set -e
        cp /build/pkg/#{GEM_FILENAME} ~/rpmbuild/SOURCES/
        cp /opt/foreman-packaging/packages/plugins/rubygem-smart_proxy_openbolt/rubygem-smart_proxy_openbolt.spec \
          ~/rpmbuild/SPECS/
        rpmbuild -ba ~/rpmbuild/SPECS/rubygem-smart_proxy_openbolt.spec
        cp ~/rpmbuild/RPMS/noarch/rubygem-smart_proxy_openbolt-*.rpm /build/pkg/
      BASH
      volumes: { Dir.pwd => '/build', foreman_packaging_path(FOREMAN_VERSION) => '/opt/foreman-packaging' },
      platform: 'linux/amd64'
    )

    rpm = Dir.glob('pkg/rubygem-smart_proxy_openbolt-*.rpm').first
    abort 'RPM build produced no output file in pkg/'.red unless rpm
    puts "RPM built: #{rpm}".green
  end

  desc 'Build DEB using foreman-packaging and Debian container'
  task deb: :gem do
    FileUtils.rm_f(Dir.glob('pkg/ruby-smart-proxy-openbolt*.deb'))
    Container.run_once(
      image: build_deb_builder_image(FOREMAN_VERSION),
      cmd: <<~BASH,
        set -e
        export DEBEMAIL="packaging@overlookinfratech.com"
        export DEBFULLNAME="Overlook InfraTech"

        BUILD_DIR=$(mktemp -d)
        cd "$BUILD_DIR"
        cp /build/pkg/#{GEM_FILENAME} .

        /opt/foreman-packaging/dependencies/gem2deb #{GEM_FILENAME} \
          --debian-subdir /opt/foreman-packaging/plugins/smart_proxy_openbolt \
          --only-source-dir

        SRCDIR=$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'ruby-smart-proxy-openbolt-*' | head -1)
        if [ -z "$SRCDIR" ]; then
          echo "ERROR: gem2deb did not create source directory in $BUILD_DIR"
          exit 1
        fi

        cd "$SRCDIR"
        echo "=== Source tree ==="
        find . -not -path './debian/*' -not -path './.git/*' | sort
        echo "=== debian/install ==="
        cat debian/install
        dpkg-buildpackage -us -uc
        cp "$BUILD_DIR"/ruby-smart-proxy-openbolt*.deb /build/pkg/
      BASH
      volumes: {
        Dir.pwd => '/build',
        foreman_packaging_path('develop', branch_prefix: 'deb') => '/opt/foreman-packaging',
      },
      platform: 'linux/amd64'
    )

    deb = Dir.glob('pkg/ruby-smart-proxy-openbolt*.deb').first
    abort 'DEB build produced no output file in pkg/'.red unless deb
    puts "DEB built: #{deb}".green
  end
end
