require 'smart_proxy_openbolt/api'

map '/openbolt' do
  run Proxy::OpenBolt::Api
end
