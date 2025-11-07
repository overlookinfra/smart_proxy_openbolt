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
  s.required_ruby_version = Gem::Requirement.new('>= 2.7')

  s.add_dependency 'concurrent-ruby', '~> 1.3', '>= 1.3.5'
end
