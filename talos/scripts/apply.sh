#!/usr/bin/env bash
set -euo pipefail

NODE_IP="192.168.18.101"
TALOSCONFIG="$(dirname $0)/../clusterconfig/talosconfig"
NODE1_CONFIG="$(dirname $0)/../clusterconfig/homelab-node1.yaml"

echo "=== Applying config to node ==="
if talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" get machinestatus &>/dev/null; then
    echo "Node already configured, applying update..."
    talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" apply-config --file "$NODE1_CONFIG"
else
    echo "Node in maintenance mode, applying initial config..."
    talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" apply-config --insecure --file "$NODE1_CONFIG"
fi

