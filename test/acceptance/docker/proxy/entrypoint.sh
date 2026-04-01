#!/bin/bash
# Entrypoint for the smart-proxy acceptance test container.
# Installs the openbolt plugin from bind-mounted source, generates SSL
# certificates, writes config files, and starts smart-proxy.
set -e

SSL_DIR="/etc/foreman-proxy/ssl"
SETTINGS_DIR="/etc/foreman-proxy/settings.d"
PLUGIN_SRC="/opt/smart_proxy_openbolt"
LOG_DIR="/var/log/foreman-proxy"
ENV_PATH="/etc/puppetlabs/code/environments/production"
PROXY_DIR="/usr/share/foreman-proxy"

# --- Install the openbolt plugin gem from bind-mounted source ---
echo "Building and installing smart_proxy_openbolt gem..."
cd "${PLUGIN_SRC}"
gem build smart_proxy_openbolt.gemspec --silent
gem install --local --no-document --no-user-install \
    --ignore-dependencies --install-dir /usr/share/gems \
    smart_proxy_openbolt-*.gem
rm -f smart_proxy_openbolt-*.gem

# Register the plugin with smart-proxy via bundler.d
cat > "${PROXY_DIR}/bundler.d/openbolt.rb" <<'BUNDLER'
gem 'smart_proxy_openbolt'
BUNDLER

# --- Generate self-signed CA and certificates ---
if [ ! -f "${SSL_DIR}/ca.pem" ]; then
    echo "Generating SSL certificates..."
    mkdir -p "${SSL_DIR}"

    # CA
    openssl genrsa -out "${SSL_DIR}/ca-key.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "${SSL_DIR}/ca-key.pem" \
        -out "${SSL_DIR}/ca.pem" -days 365 \
        -subj "/CN=Acceptance Test CA" 2>/dev/null

    # Server cert with SANs
    openssl genrsa -out "${SSL_DIR}/server-key.pem" 2048 2>/dev/null
    openssl req -new -key "${SSL_DIR}/server-key.pem" \
        -out "${SSL_DIR}/server.csr" \
        -subj "/CN=proxy" 2>/dev/null
    openssl x509 -req -in "${SSL_DIR}/server.csr" \
        -CA "${SSL_DIR}/ca.pem" -CAkey "${SSL_DIR}/ca-key.pem" \
        -CAcreateserial \
        -out "${SSL_DIR}/server.pem" -days 365 \
        -extfile <(printf "subjectAltName=DNS:proxy,DNS:localhost,IP:127.0.0.1") \
        2>/dev/null

    # Client cert (for test runner to present to WEBrick)
    openssl genrsa -out "${SSL_DIR}/client-key.pem" 2048 2>/dev/null
    openssl req -new -key "${SSL_DIR}/client-key.pem" \
        -out "${SSL_DIR}/client.csr" \
        -subj "/CN=acceptance-test-client" 2>/dev/null
    openssl x509 -req -in "${SSL_DIR}/client.csr" \
        -CA "${SSL_DIR}/ca.pem" -CAkey "${SSL_DIR}/ca-key.pem" \
        -CAcreateserial \
        -out "${SSL_DIR}/client.pem" -days 365 2>/dev/null

    rm -f "${SSL_DIR}"/*.csr "${SSL_DIR}"/*.srl
    echo "SSL certificates generated."
fi

# Set permissions on SSL files
chmod 640 "${SSL_DIR}"/*.pem
chmod 600 "${SSL_DIR}/server-key.pem" "${SSL_DIR}/client-key.pem" "${SSL_DIR}/ca-key.pem"
chown -R foreman-proxy:foreman-proxy "${SSL_DIR}"

# --- Write smart-proxy settings ---
cat > /etc/foreman-proxy/settings.yml <<EOF
---
:settings_directory: ${SETTINGS_DIR}
:ssl_certificate: ${SSL_DIR}/server.pem
:ssl_ca_file: ${SSL_DIR}/ca.pem
:ssl_private_key: ${SSL_DIR}/server-key.pem
:https_port: 8443
:bind_host:
  - '*'
:log_file: ${LOG_DIR}/proxy.log
:log_level: DEBUG
EOF

# --- Write openbolt plugin settings ---
cat > "${SETTINGS_DIR}/openbolt.yml" <<EOF
---
:enabled: https
:environment_path: ${ENV_PATH}
:workers: 5
:concurrency: 20
:connect_timeout: 30
:log_dir: ${LOG_DIR}/openbolt
EOF

# Create log directories
mkdir -p "${LOG_DIR}/openbolt"
chown -R foreman-proxy:foreman-proxy "${LOG_DIR}"

# --- Copy SSH private key for OpenBolt to use when connecting to targets ---
if [ -f /tmp/ssh/id_rsa ]; then
    cp /tmp/ssh/id_rsa /opt/foreman-proxy/.ssh/id_rsa
    chown foreman-proxy:foreman-proxy /opt/foreman-proxy/.ssh/id_rsa
    chmod 600 /opt/foreman-proxy/.ssh/id_rsa
else
    echo "WARNING: SSH private key not found at /tmp/ssh/id_rsa, SSH tasks will fail"
fi

echo "Starting smart-proxy..."
cd "${PROXY_DIR}"
exec bin/smart-proxy
