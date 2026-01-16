#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}"; }

RELATIVE_SCRIPT_DIR="$(dirname "$0")"
SCRIPT_DIR="$(realpath "$RELATIVE_SCRIPT_DIR")"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../..")"
NODE_IP="192.168.18.101"
TALOSCONFIG="$REPO_ROOT/talos/clusterconfig/talosconfig"
KUBECONFIG_PATH="$REPO_ROOT/kubeconfig"

GITHUB_USER="Axot017"
GITHUB_REPO="homelab"
GITHUB_BRANCH="main"
FLUX_PATH="./k8s/clusters/homelab"

export TALOSCONFIG
export KUBECONFIG="$KUBECONFIG_PATH"

echo -e "${CYAN}${BOLD}"
echo "=========================================="
echo "   Homelab Kubernetes Bootstrap (Flux)   "
echo "==========================================${NC}"
echo ""
log_info "SCRIPT_DIR: $SCRIPT_DIR"
log_info "REPO_ROOT: $REPO_ROOT"
log_info "TALOSCONFIG: $TALOSCONFIG"
log_info "KUBECONFIG: $KUBECONFIG_PATH"

helm_release_exists() {
    local release=$1
    local namespace=$2
    helm status "$release" -n "$namespace" &>/dev/null
}

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    log_info "Waiting for pods with label $label in $namespace..."
    if kubectl wait --for=condition=ready pod \
        -l "$label" \
        -n "$namespace" \
        --timeout="${timeout}s" &>/dev/null; then
        log_info "All pods ready!"
    else
        log_warn "Timeout waiting for pods, continuing anyway..."
    fi
}

is_cluster_bootstrapped() {
    local etcd_state
    etcd_state=$(talosctl --nodes "$NODE_IP" service etcd 2>/dev/null | grep "^STATE" | awk '{print $2}')
    [[ "$etcd_state" == "Running" ]]
}

prompt_github_token() {
    echo ""
    echo -e "Flux requires a GitHub Personal Access Token with ${BOLD}repo${NC} permissions."
    echo -e "Create one at: ${CYAN}https://github.com/settings/tokens${NC}"
    echo ""
    
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log_info "GITHUB_TOKEN already set in environment"
        read -rp "Use existing GITHUB_TOKEN? [Y/n]: " use_existing
        if [[ "${use_existing,,}" != "n" ]]; then
            return 0
        fi
    fi
    
    read -rsp "Enter GitHub Personal Access Token: " token
    echo ""
    
    if [[ -z "$token" ]]; then
        log_error "Token cannot be empty"
        exit 1
    fi
    
    export GITHUB_TOKEN="$token"
    log_info "GITHUB_TOKEN exported"
}

# Step 1: Bootstrap Talos cluster
log_step "Step 1: Bootstrap cluster"
if is_cluster_bootstrapped; then
    log_info "Cluster already bootstrapped, skipping..."
else
    log_info "Bootstrapping cluster..."
    talosctl --nodes "$NODE_IP" bootstrap
    
    log_info "Waiting for etcd to be ready..."
    until talosctl --nodes "$NODE_IP" get members &>/dev/null; do
        log_info "Waiting for etcd..."
        sleep 5
    done
    log_info "etcd is ready!"
fi

# Step 2: Get kubeconfig
log_step "Step 2: Get kubeconfig"
talosctl --nodes "$NODE_IP" kubeconfig --force "$KUBECONFIG_PATH"
log_info "Kubeconfig saved to $KUBECONFIG_PATH"

# Step 3: Wait for Kubernetes API
log_step "Step 3: Wait for Kubernetes API"
until kubectl get nodes &>/dev/null; do
    log_info "Waiting for API server..."
    sleep 10
done
log_info "Kubernetes API is ready!"

# Step 4: Install Cilium CNI
log_step "Step 4: Install Cilium CNI"
if helm_release_exists "cilium" "kube-system"; then
    log_info "Cilium already installed, skipping..."
else
    log_info "Adding Cilium Helm repo..."
    helm repo add cilium https://helm.cilium.io/ --force-update
    helm repo update
    
    log_info "Installing Cilium..."
    helm install cilium cilium/cilium \
        --namespace kube-system \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=true \
        --set k8sServiceHost=192.168.18.101 \
        --set k8sServicePort=6443 \
        --set hubble.enabled=true \
        --set hubble.relay.enabled=true \
        --set hubble.ui.enabled=true \
        --set operator.replicas=1 \
        --set l2announcements.enabled=true \
        --set externalIPs.enabled=true \
        --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
        --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
        --set cgroup.autoMount.enabled=false \
        --set cgroup.hostRoot=/sys/fs/cgroup
fi

log_info "Waiting for Cilium to be ready..."
wait_for_pods "kube-system" "app.kubernetes.io/part-of=cilium" 300

# Step 5: Wait for node to be Ready
log_step "Step 5: Wait for node to be Ready"
until kubectl get nodes | grep -q " Ready"; do
    log_info "Waiting for node to be Ready..."
    sleep 10
done
log_info "Node is Ready!"
kubectl get nodes

# Step 6: Prompt for GitHub token
log_step "Step 6: GitHub Authentication"
prompt_github_token

# Step 7: Flux pre-flight checks
log_step "Step 7: Flux pre-flight checks"
if ! flux check --pre; then
    log_error "Flux pre-flight checks failed"
    exit 1
fi
log_info "Pre-flight checks passed!"

# Step 8: Bootstrap Flux
log_step "Step 8: Bootstrap Flux"
log_info "Bootstrapping Flux to $GITHUB_USER/$GITHUB_REPO..."
flux bootstrap github \
    --owner="$GITHUB_USER" \
    --repository="$GITHUB_REPO" \
    --branch="$GITHUB_BRANCH" \
    --path="$FLUX_PATH" \
    --personal

log_info "Waiting for Flux controllers to be ready..."
wait_for_pods "flux-system" "app.kubernetes.io/part-of=flux" 300

# Complete
log_step "Bootstrap complete!"

echo ""
log_info "Cluster status:"
kubectl get nodes

echo ""
log_info "Flux status:"
flux check

echo ""
echo -e "${CYAN}${BOLD}Useful commands:${NC}"
echo "  flux get kustomizations         # Check reconciliation status"
echo "  flux get helmreleases -A        # Check HelmRelease status"
echo "  flux logs --follow              # Stream Flux logs"
echo "  flux reconcile kustomization flux-system --with-source"
echo ""
echo -e "${GREEN}Kubeconfig:${NC} export KUBECONFIG=$KUBECONFIG_PATH"
