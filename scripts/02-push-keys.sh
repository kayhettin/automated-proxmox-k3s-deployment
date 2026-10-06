#!/bin/bash
set -euo pipefail

source ../.env

# Array of targets formatted as user@host
SERVERS=(
    "root@10.10.0.11" "root@10.10.0.12" "root@10.10.0.13"
    "root@10.10.0.14" "root@10.10.0.15" "root@10.10.0.16"
    "${SSH_USER}@10.10.0.21" "${SSH_USER}@10.10.0.22" "${SSH_USER}@10.10.0.23"
    "${SSH_USER}@10.10.0.24" "${SSH_USER}@10.10.0.25" "${SSH_USER}@10.10.0.26"
)

echo "Starting SSH key distribution..."

for server in "${SERVERS[@]}"; do
    echo "Pushing to ${server}..."
    ssh -o StrictHostKeyChecking=no "${server}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo \"${SSH_PUB_KEY}\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    if [ $? -eq 0 ]; then
        echo "[ OK ] Successfully added key to ${server}"
    else
        echo "[FAIL] Could not connect to ${server}"
    fi
done

echo "Distribution complete."
