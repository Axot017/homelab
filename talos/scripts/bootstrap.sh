#!/usr/bin/env bash
set -euo pipefail

RELATIVE_SCRIPT_DIR="$(dirname $0)"
SCRIPT_DIR="$(realpath "$RELATIVE_SCRIPT_DIR")"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../..")"
NODE_IP="192.168.18.101"
TALOSCONFIG="$REPO_ROOT/talos/clusterconfig/talosconfig"
KUBECONFIG_PATH="$REPO_ROOT/kubeconfig"

echo "Using SCRIPT_DIR: $SCRIPT_DIR"
echo "Using REPO_ROOT: $REPO_ROOT"
echo "Using TALOSCONFIG: $TALOSCONFIG"
echo "Using KUBECONFIG: $KUBECONFIG_PATH"

export TALOSCONFIG
export KUBECONFIG="$KUBECONFIG_PATH"

helm_release_exists() {
    local release=$1
    local namespace=$2
    helm status "$release" -n "$namespace" &>/dev/null
}

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    echo "Waiting for pods with label $label in $namespace..."
    if kubectl wait --for=condition=ready pod \
        -l "$label" \
        -n "$namespace" \
        --timeout="${timeout}s" &>/dev/null; then
        echo "All pods ready!"
    else
        echo "Warning: Timeout waiting for pods, continuing anyway..."
    fi
}


is_cluster_bootstrapped() {
    local etcd_state
    etcd_state=$(talosctl --nodes "$NODE_IP" service etcd 2>/dev/null | grep "^STATE" | awk '{print $2}')
    [[ "$etcd_state" == "Running" ]]
}

echo "=== Step 1: Bootstrap cluster ==="
if is_cluster_bootstrapped; then
    echo "Cluster already bootstrapped, skipping..."
else
    echo "Bootstrapping cluster..."
    talosctl --nodes "$NODE_IP" bootstrap
    
    echo "Waiting for etcd to be ready..."
    until talosctl --nodes "$NODE_IP" get members &>/dev/null; do
        echo "Waiting for etcd..."
        sleep 5
    done
fi

echo ""
echo "=== Step 2: Get kubeconfig ==="
talosctl --nodes "$NODE_IP" kubeconfig --force "$KUBECONFIG_PATH"

echo ""
echo "=== Step 3: Wait for Kubernetes API ==="
until kubectl get nodes &>/dev/null; do
    echo "Waiting for API server..."
    sleep 10
done
echo "Kubernetes API is ready!"

echo ""
echo "=== Step 4: Install Cilium CNI ==="
if helm_release_exists "cilium" "kube-system"; then
    echo "Cilium already installed, skipping..."
else
    echo "Adding Cilium Helm repo..."
    helm repo add cilium https://helm.cilium.io/ --force-update
    helm repo update
    
    echo "Installing Cilium..."
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

echo "Waiting for Cilium to be ready..."
wait_for_pods "kube-system" "app.kubernetes.io/part-of=cilium" 300

echo ""
echo "=== Step 5: Wait for node to be Ready ==="
until kubectl get nodes | grep -q " Ready"; do
    echo "Waiting for node to be Ready..."
    sleep 10
done
echo "Node is Ready!"

echo ""
echo "=== Step 6: Install ArgoCD ==="
if helm_release_exists "argocd" "argocd"; then
    echo "ArgoCD already installed, skipping..."
else
    echo "Creating ArgoCD namespace..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    echo "Adding ArgoCD Helm repo..."
    helm repo add argo https://argoproj.github.io/argo-helm --force-update
    helm repo update
    
    echo "Installing ArgoCD..."
    helm install argocd argo/argo-cd \
        --namespace argocd 
fi

echo "Waiting for ArgoCD to be ready..."
wait_for_pods "argocd" "app.kubernetes.io/name=argocd-server" 300

echo ""
echo "=== Bootstrap complete! ==="
echo ""
echo "Cluster status:"
kubectl get nodes
echo ""
echo "ArgoCD credentials:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not yet available")
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "Kubeconfig: export KUBECONFIG=$KUBECONFIG_PATH"
