require 'smart_proxy_example/example_api'

map '/example' do
  run Proxy::Example::Api
end
