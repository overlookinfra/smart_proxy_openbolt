#!/bin/bash
# Setup script for the Choria target container.
# Runs during image preparation to get certs signed and Choria configured.
set -e

PRIMARY="choria-proxy"

/opt/puppetlabs/bin/puppet config set server "${PRIMARY}" --section main
/opt/puppetlabs/bin/puppet config set certname "$(hostname)" --section main

echo "Running openvox-agent to configure Choria..."
for attempt in $(seq 1 30); do
    exit_code=0
    /opt/puppetlabs/bin/puppet agent -t --server "${PRIMARY}" --waitforcert 10 || exit_code=$?
    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 2 ]; then
        echo "openvox-agent run succeeded."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "ERROR: openvox-agent failed after 30 attempts."
        exit 1
    fi
    echo "openvox-agent attempt ${attempt} failed (exit ${exit_code}), retrying in 10s..."
    sleep 10
done

echo "Starting choria-server..."
choria server run --config /etc/choria/server.conf &

echo "=== Target setup complete. ==="
wait
