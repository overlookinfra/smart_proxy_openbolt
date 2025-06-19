require File.expand_path('../lib/smart_proxy_bolt/version', __FILE__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_bolt'
  s.version = Proxy::Bolt::VERSION

  s.summary = 'Smart Proxy plugin for Bolt integration'
  s.description = 'Uses the Bolt CLI tool to run tasks and plans in Foreman'
  s.authors = ['Overlook InfraTech']
  s.email = 'contact@overlookinfratech.com'
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = Dir['{lib,settings.d,bundler.d}/**/*'] + s.extra_rdoc_files
  s.homepage = 'http://github.com/overlookinfra/smart_proxy_bolt'
  s.license = 'GPLv3'
end
