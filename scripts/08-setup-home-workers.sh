#!/usr/bin/env bash
# =====================================================
# SETUP HOME WORKERS
# Labels home workers and deploys home-specific workloads
# =====================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "STARO MODULAR - HOME WORKERS SETUP"
echo "=============================================="
echo ""

# =====================================================
# Label Home Workers
# =====================================================
echo "=== Labeling Home Workers ==="

# Label nodes with location=home (if not already)
kubectl label node kube01 location=home --overwrite 2>/dev/null || true
kubectl label node techadmin-proliant-ml310e-gen8-v2 location=home --overwrite 2>/dev/null || true

echo "✓ Home workers labeled"
echo ""

# Verify labels
echo "=== Node Labels ==="
kubectl get nodes -l location=home -o wide
echo ""

# =====================================================
# Create GHCR secret in home-monitoring namespace
# =====================================================
echo "=== Creating Secrets for Home Workers ==="
kubectl create namespace home-monitoring --dry-run=client -o yaml | kubectl apply -f -

# Copy GHCR secret if exists
if kubectl -n prod-backend get secret ghcr-secret &>/dev/null; then
    kubectl get secret ghcr-secret -n prod-backend -o yaml | \
        sed 's/namespace: prod-backend/namespace: home-monitoring/' | \
        kubectl apply -f - 2>/dev/null || true
    echo "✓ GHCR secret copied to home-monitoring"
fi
echo ""

# =====================================================
# Deploy Home Worker Celery
# =====================================================
echo "=== Deploying Celery on Home Workers ==="
kubectl apply -f "$K8S_DIR/backend/celery-home.yaml"
echo "Note: Celery pods will be scheduled on home workers (location=home)"
echo ""

# =====================================================
# Deploy Monitoring for Home Workers
# =====================================================
echo "=== Deploying Monitoring on Home Workers ==="
kubectl apply -f "$K8S_DIR/home-workers/monitoring.yaml"
echo ""

# =====================================================
# Summary
# =====================================================
echo "=============================================="
echo "✅ Home Workers Setup Complete!"
echo "=============================================="
echo ""

echo "=== Home Worker Pods ==="
sleep 3
kubectl get pods -A -o wide --field-selector spec.nodeName=kube01 2>/dev/null || true
kubectl get pods -A -o wide --field-selector spec.nodeName=techadmin-proliant-ml310e-gen8-v2 2>/dev/null || true
echo ""

echo "=== Celery Home Workers ==="
kubectl -n prod-backend get pods -l app=celery-home -o wide 2>/dev/null || echo "Pending..."
echo ""

echo "=== Next Steps ==="
echo "1. Update HAProxy on master node:"
echo "   scp k8s/lb/haproxy.cfg root@<master>:/etc/haproxy/haproxy.cfg"
echo "   ssh root@<master> 'systemctl reload haproxy'"
echo ""
echo "2. Verify home worker is receiving Celery tasks:"
echo "   kubectl -n prod-backend logs -l app=celery-home --tail=50"
echo ""
