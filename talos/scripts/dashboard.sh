#!/usr/bin/env bash
set -euo pipefail

NODE_IP="192.168.18.101"
TALOSCONFIG="$(dirname $0)/../clusterconfig/talosconfig"
NODE1_CONFIG="$(dirname $0)/../clusterconfig/homelab-node1.yaml"

talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" dashboard
