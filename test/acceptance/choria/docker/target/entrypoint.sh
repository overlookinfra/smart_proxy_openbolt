#!/bin/bash
# Entrypoint for the prepared Choria target container.
# Starts choria-server only — all setup was done during image preparation.
set -e

exec choria server run --config /etc/choria/server.conf
