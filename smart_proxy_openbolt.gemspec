require File.expand_path('../lib/smart_proxy_openbolt/version', __FILE__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_openbolt'
  s.version = Proxy::OpenBolt::VERSION

  s.summary = 'Smart Proxy plugin for OpenBolt integration'
  s.description = 'Uses the OpenBolt CLI tool to run tasks and plans in Foreman'
  s.authors = ['Overlook InfraTech']
  s.email = 'contact@overlookinfratech.com'
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = Dir['{lib,settings.d,bundler.d}/**/*'] + s.extra_rdoc_files
  s.homepage = 'http://github.com/overlookinfra/smart_proxy_openbolt'
  s.license = 'GPL-3.0-only'
  s.required_ruby_version = Gem::Requirement.new('>= 3.0')

  # we need to allow 1.1.6
  # dynflow depends on it https://rubygems.org/gems/dynflow/versions/1.9.3
  # On EL, foreman packages a modern concurrent-ruby package
  # on Debian/Ubuntu, they rely on the upstream packages, and debian.org packages 1.1.6 on bookworm, that's the oldest supported distro/version right now
  # https://packages.debian.org/bookworm/ruby-concurrent
  s.add_dependency 'concurrent-ruby', '>= 1.1.6', '< 2'
end
