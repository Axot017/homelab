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

## Scenario 6: PostgreSQL Database Recovery (CloudNativePG)

PostgreSQL databases are managed by CloudNativePG and have their own backup system separate from Velero. Backups are stored in S3 at `s3://mateuszledwon-homelab-backup/postgres/<app-name>/`.

### Check Available Backups

```bash
# List backup status for a cluster
kubectl get cluster nextcloud-postgres -n nextcloud -o yaml | grep -A 20 "status:"

# Check the first recoverable point
kubectl get cluster nextcloud-postgres -n nextcloud -o jsonpath='{.status.firstRecoverablePoint}'

# Check the last successful backup
kubectl get cluster nextcloud-postgres -n nextcloud -o jsonpath='{.status.lastSuccessfulBackup}'
```

### Point-in-Time Recovery (PITR)

To recover to a specific point in time, create a new cluster that recovers from the backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: nextcloud-postgres-recovered
  namespace: nextcloud
spec:
  instances: 1
  
  storage:
    storageClass: longhorn
    size: 10Gi
  
  bootstrap:
    recovery:
      source: nextcloud-postgres-backup
      # Optional: recover to specific point in time
      # recoveryTarget:
      #   targetTime: "2024-01-09T10:30:00Z"
  
  externalClusters:
    - name: nextcloud-postgres-backup
      barmanObjectStore:
        destinationPath: s3://mateuszledwon-homelab-backup/postgres/nextcloud
        s3Credentials:
          accessKeyId:
            name: postgres-s3-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: postgres-s3-credentials
            key: SECRET_ACCESS_KEY
        wal:
          compression: gzip
        data:
          compression: gzip
```

Save as `recovery.yaml` and apply:

```bash
kubectl apply -f recovery.yaml

# Watch recovery progress
kubectl get cluster -n nextcloud -w

# Check logs
kubectl logs -n nextcloud -l cnpg.io/cluster=nextcloud-postgres-recovered -f
```

### Switch Application to Recovered Database

Once recovery is complete:

1. Update the application to point to the new database:
```bash
# The new service will be: nextcloud-postgres-recovered-rw.nextcloud.svc.cluster.local
# Update your application's database host configuration
```

2. Or rename clusters (requires brief downtime):
```bash
# Delete old cluster
kubectl delete cluster nextcloud-postgres -n nextcloud

# Rename recovered cluster (edit the YAML and reapply)
kubectl get cluster nextcloud-postgres-recovered -n nextcloud -o yaml | \
  sed 's/nextcloud-postgres-recovered/nextcloud-postgres/g' | \
  kubectl apply -f -
```

### Full Cluster Rebuild with PostgreSQL Recovery

During disaster recovery, after the CNPG operator is running:

1. First, ensure the S3 credentials secret exists (apply sealed secret)

2. Create recovery cluster instead of fresh bootstrap:
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: nextcloud-postgres
  namespace: nextcloud
spec:
  instances: 1
  storage:
    storageClass: longhorn
    size: 10Gi
  
  # Use recovery bootstrap instead of initdb
  bootstrap:
    recovery:
      source: nextcloud-postgres-backup
  
  externalClusters:
    - name: nextcloud-postgres-backup
      barmanObjectStore:
        destinationPath: s3://mateuszledwon-homelab-backup/postgres/nextcloud
        s3Credentials:
          accessKeyId:
            name: postgres-s3-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: postgres-s3-credentials
            key: SECRET_ACCESS_KEY
        wal:
          compression: gzip
        data:
          compression: gzip
```
