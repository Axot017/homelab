#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
NODE_IP="192.168.18.101"
TALOSCONFIG="$REPO_ROOT/talos/clusterconfig/talosconfig"
NODE1_CONFIG="$REPO_ROOT/talos/clusterconfig/homelab-node1.yaml"
DEFAULT_KUBECONFIG="$REPO_ROOT/kubeconfig"
SEALED_SECRETS_KEY="$REPO_ROOT/backup/sealed-secrets-key.yaml"
SEALED_SECRETS_KEY_SOPS="$REPO_ROOT/backup/sealed-secrets-key.sops.yaml"

apply_backup_sealed_secrets_key() {
    local backup_file=""
    local apply_choice=""
    local kubeconfig_path="${KUBECONFIG:-$DEFAULT_KUBECONFIG}"

    if [[ -f "$SEALED_SECRETS_KEY" ]]; then
        backup_file="$SEALED_SECRETS_KEY"
    elif [[ -f "$SEALED_SECRETS_KEY_SOPS" ]]; then
        backup_file="$SEALED_SECRETS_KEY_SOPS"
    else
        echo "=== No backup sealed secrets key found in $REPO_ROOT/backup, skipping ==="
        return 0
    fi

    echo ""
    read -rp "Backup sealed secrets key found at $backup_file. Apply it now? [y/N]: " apply_choice
    if [[ ! "$apply_choice" =~ ^[Yy]$ ]]; then
        echo "Skipping backup sealed secrets key apply"
        return 0
    fi

    if [[ ! -f "$kubeconfig_path" ]]; then
        echo "Kubeconfig not found at $kubeconfig_path, skipping backup sealed secrets key apply"
        return 0
    fi

    echo "=== Applying backup sealed secrets key ==="
    if [[ "$backup_file" == "$SEALED_SECRETS_KEY_SOPS" ]]; then
        if ! command -v sops &>/dev/null; then
            echo "sops is required to decrypt $SEALED_SECRETS_KEY_SOPS, skipping"
            return 0
        fi

        sops -d "$backup_file" | kubectl --kubeconfig "$kubeconfig_path" apply -f -
    else
        kubectl --kubeconfig "$kubeconfig_path" apply -f "$backup_file"
    fi
}

echo "=== Applying config to node ==="
if talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" get machinestatus &>/dev/null; then
    echo "Node already configured, applying update..."
    talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" apply-config --file "$NODE1_CONFIG"
else
    echo "Node in maintenance mode, applying initial config..."
    talosctl --talosconfig "$TALOSCONFIG" --nodes "$NODE_IP" apply-config --insecure --file "$NODE1_CONFIG"
fi

apply_backup_sealed_secrets_key

