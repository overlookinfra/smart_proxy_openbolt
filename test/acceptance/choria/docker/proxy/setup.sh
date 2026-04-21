#!/bin/bash
# Setup script for the Choria proxy container.
# Runs during image preparation to install modules, generate certs,
# configure Choria via openvox-agent, and start services.
# After setup, keeps services running so targets can connect.
set -e

PUPPET_SSL="/etc/puppetlabs/puppet/ssl"
ENV_PATH="/etc/puppetlabs/code/environments/production"
PROXY_HOSTNAME="$(hostname)"

# --- Install local RPMs if present (temporary, for development) ---
if ls /opt/rpms/*.rpm 1>/dev/null 2>&1; then
    echo "Installing local RPMs..."
    dnf install -y /opt/rpms/*.rpm
fi

# --- Deploy Puppet modules with r10k ---
echo "Deploying modules with r10k..."
cd "${ENV_PATH}"
/opt/puppetlabs/puppet/bin/r10k puppetfile install --verbose

# --- Start OpenVox Server ---
echo "Starting OpenVox Server..."
/opt/puppetlabs/bin/puppetserver foreground &

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

# --- Configure openvox-agent ---
/opt/puppetlabs/bin/puppet config set server "${PROXY_HOSTNAME}" --section main
/opt/puppetlabs/bin/puppet config set certname "${PROXY_HOSTNAME}" --section main

# --- Generate certificates ---
echo "Generating certificate for foreman-proxy.mcollective..."
/opt/puppetlabs/bin/puppetserver ca generate --certname foreman-proxy.mcollective

echo "Generating certificate for acceptance-test-client..."
/opt/puppetlabs/bin/puppetserver ca generate --certname acceptance-test-client

# --- Run openvox-agent to configure Choria broker ---
echo "Running openvox-agent to configure Choria..."
exit_code=0
/opt/puppetlabs/bin/puppet agent -t --server "${PROXY_HOSTNAME}" || exit_code=$?
if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 2 ]; then
    echo "ERROR: openvox-agent run failed with exit code ${exit_code}."
    exit 1
fi
echo "openvox-agent run completed (exit ${exit_code})."

# --- Start Choria broker ---
echo "Starting Choria broker..."
choria broker run --config /etc/choria/broker.conf &

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

# --- SSL permissions for foreman-proxy ---
usermod -aG puppet foreman-proxy
chmod 640 "${PUPPET_SSL}/private_keys/"*.pem

# --- Write Choria client config ---
cat > /opt/foreman-proxy/.choriarc <<EOF
collectives = mcollective
main_collective = mcollective
connector = nats
identity = foreman-proxy.mcollective
libdir = /opt/puppetlabs/mcollective/plugins
logger_type = console
loglevel = warn
securityprovider = choria
plugin.choria.middleware_hosts = nats://${PROXY_HOSTNAME}:4222
plugin.security.provider = file
plugin.security.file.certificate = ${PUPPET_SSL}/certs/foreman-proxy.mcollective.pem
plugin.security.file.key = ${PUPPET_SSL}/private_keys/foreman-proxy.mcollective.pem
plugin.security.file.ca = ${PUPPET_SSL}/certs/ca.pem
EOF
chown foreman-proxy:foreman-proxy /opt/foreman-proxy/.choriarc

# --- Create log directories ---
mkdir -p /var/log/foreman-proxy/openbolt
chown -R foreman-proxy:foreman-proxy /var/log/foreman-proxy

echo "=== Proxy setup complete. Services running for target setup. ==="

# Keep running so targets can connect
wait
