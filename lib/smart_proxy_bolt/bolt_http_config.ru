require 'smart_proxy_bolt/bolt_api'

map '/bolt' do
  run Proxy::Bolt::Api
end
