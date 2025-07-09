require File.expand_path('../lib/smart_proxy_example/version', __FILE__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_example'
  s.version = Proxy::Example::VERSION

  s.summary = 'Example smart proxy plugin'
  s.description = 'Example smart proxy plugin'
  s.authors = ['John Doe']
  s.email = 'john.doe@example.com'
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = Dir['{lib,settings.d,bundler.d}/**/*'] + s.extra_rdoc_files
  s.homepage = 'http://github.com/johndoe/smart_proxy_example'
  s.license = 'GPLv3'
end
