require 'test_helper'
require 'webmock/test_unit'
require 'mocha/test_unit'
require 'rack/test'

require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/api'

class OpenBoltApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::OpenBolt::Api.new
  end

  def test_returns_hello_greeting
    # add test here
  end

end
