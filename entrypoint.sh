#!/bin/bash
# Fix Docker socket permissions for oxker
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

# Execute the command passed to this container
exec "$@"