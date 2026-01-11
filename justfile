default:
    @just --list

pfall:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Starting all port forwards..."
    echo "Press Ctrl+C to stop all"
    echo ""
    echo "Services:"
    echo "  ArgoCD:     http://localhost:8080"
    echo "  Grafana:    http://localhost:8081"
    echo "  Longhorn:   http://localhost:8082"
    echo ""
    
    kubectl port-forward svc/argocd-server -n argocd 8080:80 &
    kubectl port-forward svc/prometheus-stack-grafana -n monitoring 8081:80 &
    kubectl port-forward svc/longhorn-frontend -n longhorn-system 8082:80 &

    trap "kill 0" SIGINT SIGTERM
    wait

pfargocd:
    kubectl port-forward svc/argocd-server -n argocd 8080:80

pfgrafana:
    kubectl port-forward svc/prometheus-stack-grafana -n monitoring 8081:80

pflonghorn:
    kubectl port-forward svc/longhorn-frontend -n longhorn-system 8082:80

seal path:
    #!/usr/bin/env bash
    set -euo pipefail
    
    input="{{path}}"
    
    if [[ ! -f "$input" ]]; then
        echo "Error: File '$input' not found"
        exit 1
    fi
    
    # Generate output filename: *secret.yaml -> *sealed-secret.yaml
    output="${input/secret.yaml/sealed-secret.yaml}"
    
    if [[ "$input" == "$output" ]]; then
        echo "Error: Input file must end with 'secret.yaml'"
        exit 1
    fi
    
    echo "Sealing: $input -> $output"
    
    kubeseal \
        --controller-name=sealed-secrets-controller \
        --controller-namespace=kube-system \
        --format=yaml \
        < "$input" \
        > "$output"
    
    echo "✓ Sealed secret created: $output"
    echo ""
    echo "Remember: Don't commit $input (should be in .gitignore)"

unseal path:
    #!/usr/bin/env bash
    set -euo pipefail
    
    input="{{path}}"
    
    if [[ ! -f "$input" ]]; then
        echo "Error: File '$input' not found"
        exit 1
    fi
    
    # Generate output filename: *sealed-secret.yaml -> *secret.yaml
    output="${input/sealed-secret.yaml/secret.yaml}"
    
    if [[ "$input" == "$output" ]]; then
        echo "Error: Input file must end with 'sealed-secret.yaml'"
        exit 1
    fi
    
    # Extract secret name and namespace from sealed secret
    name=$(yq -r '.metadata.name' "$input")
    namespace=$(yq -r '.metadata.namespace' "$input")
    
    echo "Fetching secret '$name' from namespace '$namespace'..."
    
    kubectl get secret "$name" -n "$namespace" -o yaml | \
        yq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields, .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])' \
        > "$output"
    
    echo "✓ Secret saved to: $output"
    echo ""
    echo "⚠ Warning: This file contains sensitive data. Don't commit it!"
