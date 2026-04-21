require 'test/unit'
require 'net/http'
require 'openssl'
require 'json'
require 'uri'

# Base class for acceptance tests that make real HTTPS requests to a
# smart-proxy instance running in a Docker container.
class AcceptanceTestCase < Test::Unit::TestCase
  PROXY_HOST = ENV.fetch('PROXY_HOST', 'localhost')
  PROXY_PORT = ENV.fetch('PROXY_PORT', '8443').to_i
  SSL_DIR = ENV.fetch('SSL_DIR', File.expand_path('ssl-export', __dir__))

  def setup
    skip_unless_proxy
  end

  # --- HTTP client ---

  def http_client
    @http_client ||= build_http_client
  end

  def api_get(path)
    response = http_client.get("/openbolt#{path}")
    [response, parse_body(response)]
  end

  def api_post(path, body)
    request = Net::HTTP::Post.new("/openbolt#{path}")
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
    response = http_client.request(request)
    [response, parse_body(response)]
  end

  def api_delete(path)
    response = http_client.delete("/openbolt#{path}")
    [response, parse_body(response)]
  end

  # --- Job lifecycle helpers ---

  def poll_job_status(job_id)
    response, parsed = api_get("/job/#{job_id}/status")
    assert response.is_a?(Net::HTTPSuccess),
      "GET /job/#{job_id}/status returned #{response.code}: #{response.body}"
    assert parsed.key?('status'),
      "Expected 'status' key in response, got: #{parsed}"
    parsed['status']
  end

  def wait_for_job(job_id, timeout: 60)
    deadline = Time.now + timeout
    loop do
      status = poll_job_status(job_id)
      return status unless %w[pending running].include?(status)
      raise "Job #{job_id} did not complete within #{timeout}s" if Time.now > deadline
      sleep 0.5
    end
  end

  def wait_for_jobs(job_ids, timeout: 60)
    deadline = Time.now + timeout
    results = {}
    remaining = job_ids.dup
    until remaining.empty?
      raise "Jobs #{remaining} did not complete within #{timeout}s" if Time.now > deadline
      remaining.each do |job_id|
        next if results.key?(job_id)
        status = poll_job_status(job_id)
        results[job_id] = status unless %w[pending running].include?(status)
      end
      remaining -= results.keys
      sleep 0.5 unless remaining.empty?
    end
    job_ids.map { |job_id| results[job_id] }
  end

  def launch_task(name:, targets:, parameters: {}, options: {})
    payload = {
      'name' => name,
      'parameters' => parameters,
      'targets' => targets,
      'options' => options,
    }
    response, parsed = api_post('/launch/task', payload)
    assert response.is_a?(Net::HTTPSuccess),
      "launch_task failed (#{response.code}): #{response.body}"
    assert parsed.key?('id'), "Expected 'id' in launch response, got: #{parsed}"
    parsed['id']
  end

  # --- Transport configuration ---
  # Bolt runs inside the proxy container and connects to targets by Docker
  # service name on port 22 (the container's internal port).

  def self.transport
    ENV['ACCEPTANCE_TRANSPORT']
  end

  def transport_targets
    case self.class.transport
    when 'ssh' then ssh_targets
    when 'choria' then choria_targets
    else raise "Unknown transport '#{self.class.transport}'. Supported: ssh, choria"
    end
  end

  def transport_options
    case self.class.transport
    when 'ssh' then ssh_options
    when 'choria' then choria_options
    else raise "Unknown transport '#{self.class.transport}'. Supported: ssh, choria"
    end
  end

  def ssh_targets
    %w[target1:22 target2:22]
  end

  def ssh_options
    {
      'transport' => 'ssh',
      'user' => 'openbolt',
      'host-key-check' => false,
      'private-key' => '/opt/foreman-proxy/.ssh/id_rsa',
    }
  end

  def choria_targets
    %w[choria-target1 choria-target2]
  end

  def choria_options
    {
      'transport' => 'choria',
      'choria-task-agent' => 'shell',
    }
  end

  # --- Skip logic ---

  def self.proxy_available?
    return @proxy_available if instance_variable_defined?(:@proxy_available)
    require 'socket'
    TCPSocket.new(PROXY_HOST, PROXY_PORT).close
    @proxy_available = true
  rescue SystemCallError, SocketError => e
    @proxy_check_error = e
    @proxy_available = false
  end

  def skip_unless_proxy
    unless self.class.proxy_available?
      error = self.class.instance_variable_get(:@proxy_check_error)
      detail = " (#{error.class}: #{error.message})" if error
      omit("Proxy not reachable at #{PROXY_HOST}:#{PROXY_PORT}#{detail}")
    end
    omit('ACCEPTANCE_TRANSPORT not set') unless self.class.transport
  end

  private

  def build_http_client
    client = Net::HTTP.new(PROXY_HOST, PROXY_PORT)
    client.use_ssl = true
    client.open_timeout = 5
    client.read_timeout = 60

    # WEBrick is configured with SSLVerifyClient => VERIFY_PEER, which requests
    # a client certificate. Provide one to match production behavior.
    client_cert = File.join(SSL_DIR, 'client.pem')
    client_key = File.join(SSL_DIR, 'client-key.pem')
    ca_cert = File.join(SSL_DIR, 'ca.pem')
    raise "Client certs not found in #{SSL_DIR}. Are the containers running?" \
      unless File.exist?(client_cert) && File.exist?(client_key)

    client.cert = OpenSSL::X509::Certificate.new(File.read(client_cert))
    client.key = OpenSSL::PKey.read(File.read(client_key))

    # Skip server cert verification. The proxy uses either a self-signed
    # cert (SSH) or a Puppet CA cert whose CN doesn't include localhost
    # (Choria). Client cert auth is what matters -- the server verifies
    # our cert against its trusted_hosts list.
    client.verify_mode = OpenSSL::SSL::VERIFY_NONE

    client
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    flunk "Expected JSON response but got non-JSON body " \
          "(HTTP #{response.code} #{response.message}): " \
          "#{response.body.to_s.slice(0, 500)}\n" \
          "Parse error: #{e.message}"
  end
end
