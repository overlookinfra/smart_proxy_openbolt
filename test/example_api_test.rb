require 'test_helper'
require 'webmock/test_unit'
require 'mocha/test_unit'
require 'rack/test'

require 'smart_proxy_bolt/bolt'
require 'smart_proxy_bolt/bolt_api'

class BoltApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::Bolt::Api.new
  end

  def test_returns_hello_greeting
    # add test here
  end

end
