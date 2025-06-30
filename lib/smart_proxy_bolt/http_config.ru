require 'smart_proxy_bolt/api'

map '/bolt' do
  run Proxy::Bolt::Api
end
