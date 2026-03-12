# Homelab Kubernetes Cluster

GitOps-managed Kubernetes homelab running on Talos Linux.

## Architecture Overview

```
Internet
    │
    ▼
Cloudflare Tunnel
    │
    ▼
Envoy Gateway (192.168.18.111)
    │
    ▼
HTTPRoutes → Services → Pods
```


# Disaster Recovery

## Scenario 1: Node Failure (Recoverable)

**Symptoms**: Node NotReady, pods rescheduling

**Recovery**:
```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# If node is recoverable, reboot via Talos
talosctl reboot --nodes <node-ip>

# If node needs reinstall
talosctl apply-config --nodes <node-ip> --file talos/clusterconfig/homelab-<node>.yaml
```

---

## Scenario 2: Complete Cluster Rebuild

**Symptoms**: Total cluster loss, starting from scratch

### Prerequisites

- Access to this Git repository
- SOPS key to decrypt `backup/sealed-secrets-key.sops.yaml`
- Talos configuration files
- AWS credentials for Velero (to restore backups)

### Step 1: Rebuild Talos Cluster

```bash
cd talos

# Generate configs (if needed)
talhelper genconfig

# Apply to nodes (./talos/scripts/apply.sh)
talosctl apply-config --nodes 192.168.18.101 --file clusterconfig/homelab-node1.yaml --insecure

# Bootstrap cluster (first node only) (./talos/scripts/bootstrap.sh)
talosctl bootstrap --nodes 192.168.18.101
```

### Step 2: Install ArgoCD

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Step 3: Restore Sealed Secrets Key

This must be done BEFORE applying the ApplicationSet, otherwise secrets won't decrypt.

```bash
# Decrypt the sealed secrets key
sops -d backup/sealed-secrets-key.sops.yaml > backup/sealed-secrets-key.yaml

# Apply the key
kubectl apply -f backup/sealed-secrets-key.yaml
```

### Step 4: Apply ArgoCD Configuration

```bash
# Apply the projects
kubectl apply -f kubernetes/apps/argocd/homelab.yaml
kubectl apply -f kubernetes/apps/argocd/services.yaml
# ...

# Apply the ApplicationSet (discovers and deploys all apps)
kubectl apply -f kubernetes/apps/argocd/applicationset.yaml
```

### Step 5: Wait for Core Services

```bash
# Watch applications sync
kubectl get applications -n argocd -w

# Key apps to wait for:
# 1. sealed-secrets (must be first to decrypt other secrets)
# 2. longhorn (storage for PVCs)
# 3. metallb (LoadBalancer IPs)
```

### Step 6: Restore Data from Velero Backup

Once Velero is running:

```bash
# Check available backups
velero backup get

# Restore from latest backup
velero restore create --from-backup <backup-name>

# Or restore specific namespaces
velero restore create --from-backup <backup-name> --include-namespaces monitoring,cloudflare
```

### Step 7: Verify Recovery

```bash
# Check all pods are running
kubectl get pods -A | grep -v Running

# Check PVCs are bound
kubectl get pvc -A

# Check storage
kubectl get volumes -n longhorn-system

# Check external access
curl -I https://argocd.mateuszledwon.com  # (if HTTPRoute is configured)
```

---

## Scenario 5: Restore Single Application from Backup

```bash
# List available backups
kubectl get backups -n velero

# Restore specific namespace
velero restore create --from-backup daily-full-backup-20240109030000 \
  --include-namespaces my-app-namespace

# Check restore status
velero restore get
```

---
