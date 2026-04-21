#!/bin/bash
# Entrypoint for the prepared Choria proxy container.
# Starts services only — all setup was done during image preparation.
set -e

declare -a PROC_NAMES=()
declare -a PROC_PIDS=()

record_proc() {
    PROC_NAMES+=("$1")
    PROC_PIDS+=("$2")
}

cleanup() {
    for pid in "${PROC_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

SETTINGS_DIR="/etc/foreman-proxy/settings.d"
PLUGIN_SRC="/opt/smart_proxy_openbolt"
LOG_DIR="/var/log/foreman-proxy"
ENV_PATH="/etc/puppetlabs/code/environments/production"
PROXY_DIR="/usr/share/foreman-proxy"
PUPPET_SSL="/etc/puppetlabs/puppet/ssl"
PROXY_HOSTNAME="$(hostname)"

# --- Install the openbolt plugin gem from bind-mounted source ---
echo "Building and installing smart_proxy_openbolt gem..."
cd "${PLUGIN_SRC}"
gem build smart_proxy_openbolt.gemspec --silent
gem install --local --no-document --no-user-install \
    --ignore-dependencies --install-dir /usr/share/gems \
    smart_proxy_openbolt-*.gem
rm -f smart_proxy_openbolt-*.gem

cat > "${PROXY_DIR}/bundler.d/openbolt.rb" <<'BUNDLER'
gem 'smart_proxy_openbolt'
BUNDLER

# --- Write smart-proxy settings ---
cat > /etc/foreman-proxy/settings.yml <<EOF
---
:settings_directory: ${SETTINGS_DIR}
:ssl_certificate: ${PUPPET_SSL}/certs/${PROXY_HOSTNAME}.pem
:ssl_ca_file: ${PUPPET_SSL}/certs/ca.pem
:ssl_private_key: ${PUPPET_SSL}/private_keys/${PROXY_HOSTNAME}.pem
:trusted_hosts:
  - acceptance-test-client
:https_port: 8443
:bind_host:
  - '*'
:log_file: STDOUT
:log_level: DEBUG
EOF

cat > "${SETTINGS_DIR}/openbolt.yml" <<EOF
---
:enabled: https
:environment_path: ${ENV_PATH}
:workers: 5
:concurrency: 20
:connect_timeout: 30
:log_dir: ${LOG_DIR}/openbolt
EOF

# --- Start OpenVox Server ---
echo "Starting OpenVox Server..."
/opt/puppetlabs/bin/puppetserver foreground &
record_proc openvox-server $!

echo "Waiting for OpenVox Server to accept connections..."
for attempt in $(seq 1 60); do
    if curl -sfk "https://localhost:8140/status/v1/services" > /dev/null 2>&1; then
        echo "OpenVox Server is ready."
        break
    fi
    if [ "$attempt" -eq 60 ]; then
        echo "ERROR: OpenVox Server failed to start within 300 seconds."
        exit 1
    fi
    sleep 5
done

# --- Start Choria broker ---
echo "Starting Choria broker..."
choria broker run --config /etc/choria/broker.conf &
record_proc choria-broker $!

echo "Waiting for NATS broker on port 4222..."
for attempt in $(seq 1 30); do
    if (echo > /dev/tcp/localhost/4222) 2>/dev/null; then
        echo "NATS broker is ready."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "ERROR: NATS broker failed to start."
        exit 1
    fi
    sleep 2
done

# --- Start smart-proxy as the foreman-proxy user ---
echo "Starting smart-proxy as foreman-proxy..."
cd "${PROXY_DIR}"
su -s /bin/bash foreman-proxy -c "cd ${PROXY_DIR} && exec bin/smart-proxy" &
record_proc smart-proxy $!

# --- Supervise ---
wait -n "${PROC_PIDS[@]}"
exited_code=$?
for i in "${!PROC_PIDS[@]}"; do
    if ! kill -0 "${PROC_PIDS[$i]}" 2>/dev/null; then
        echo "ERROR: ${PROC_NAMES[$i]} (pid ${PROC_PIDS[$i]}) exited with code ${exited_code}."
        break
    fi
done
exit 1
