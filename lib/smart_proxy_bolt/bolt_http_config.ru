require 'smart_proxy_bolt/bolt_api'

map '/example' do
  run Proxy::Bolt::Api
end
