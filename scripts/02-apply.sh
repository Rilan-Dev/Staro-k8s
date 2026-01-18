#!/usr/bin/env bash
# =====================================================
# APPLY ALL MANIFESTS SCRIPT
# Deploys the entire Staro Modular platform
# =====================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "STARO MODULAR - APPLY ALL MANIFESTS"
echo "=============================================="
echo ""

# Function to apply and wait for rollout
apply_and_wait() {
    local dir="$1"
    local namespace="$2"
    local resource_type="${3:-deployment}"
    local resource_name="${4:-}"
    
    echo "=== Applying $dir ==="
    kubectl apply -f "$K8S_DIR/$dir/" --recursive 2>/dev/null || kubectl apply -f "$K8S_DIR/$dir/"
    
    if [[ -n "$resource_name" ]]; then
        echo "Waiting for $resource_type/$resource_name in $namespace..."
        kubectl -n "$namespace" rollout status "$resource_type/$resource_name" --timeout=600s || true
    fi
    echo ""
}

# =====================================================
# Phase 1: Namespaces and Storage
# =====================================================
echo "=== Phase 1: Namespaces and Storage ==="
kubectl apply -f "$K8S_DIR/namespaces/"
kubectl apply -f "$K8S_DIR/database/local-storageclass.yaml"
kubectl apply -f "$K8S_DIR/database/postgres-pv.yaml"
echo ""

# =====================================================
# Phase 2: Database Layer
# =====================================================
echo "=== Phase 2: Database Layer ==="
kubectl apply -f "$K8S_DIR/database/postgres-statefulset.yaml"
echo "Waiting for PostgreSQL..."
kubectl -n prod-database rollout status statefulset/postgres --timeout=600s || true

kubectl apply -f "$K8S_DIR/database/pgbouncer.yaml"
echo "Waiting for PgBouncer..."
kubectl -n prod-database rollout status deployment/pgbouncer --timeout=300s || true
echo ""

# =====================================================
# Phase 3: Backend Services
# =====================================================
echo "=== Phase 3: Backend Services ==="

# Redis first (Celery depends on it)
kubectl apply -f "$K8S_DIR/backend/redis.yaml"
echo "Waiting for Redis..."
kubectl -n prod-backend rollout status deployment/redis --timeout=300s || true

# RBAC for Django (needed for K8s Ingress management)
kubectl apply -f "$K8S_DIR/backend/django-rbac.yaml"
echo "Django RBAC configured"

# Django API
kubectl apply -f "$K8S_DIR/backend/django-deployment.yaml"
echo "Waiting for Django API..."
kubectl -n prod-backend rollout status deployment/django-api --timeout=600s || true

# Celery workers (after Django)
kubectl apply -f "$K8S_DIR/backend/celery.yaml"
echo "Waiting for Celery..."
kubectl -n prod-backend rollout status deployment/celery --timeout=600s || true
kubectl -n prod-backend rollout status deployment/celery-beat --timeout=600s || true
echo ""

# =====================================================
# Phase 4: Frontend
# =====================================================
echo "=== Phase 4: Frontend ==="
kubectl apply -f "$K8S_DIR/frontend/"
echo "Waiting for Frontend..."
kubectl -n prod-staro-modular rollout status deployment/staro-modular --timeout=600s || true
echo ""

# =====================================================
# Phase 5: Ingress and Certificates
# =====================================================
echo "=== Phase 5: Ingress and Certificates ==="
kubectl apply -f "$K8S_DIR/ingress/multi-tenant-ingress.yaml"
echo "Ingress applied. Certificate provisioning may take 1-2 minutes..."
echo ""

# =====================================================
# Phase 6: Network Policies
# =====================================================
echo "=== Phase 6: Network Policies ==="
kubectl apply -f "$K8S_DIR/network/"
echo ""

# =====================================================
# Phase 7: Resource Quotas
# =====================================================
echo "=== Phase 7: Resource Quotas ==="
kubectl apply -f "$K8S_DIR/policies/"
echo ""

# =====================================================
# Phase 8: External-DNS (if Cloudflare token exists)
# =====================================================
echo "=== Phase 8: External-DNS ==="
if kubectl -n kube-system get secret cloudflare-api-token &>/dev/null; then
    kubectl apply -f "$K8S_DIR/external-dns/"
    echo "External-DNS deployed"
else
    echo "⚠ Cloudflare API token not found, skipping External-DNS"
fi
echo ""

# =====================================================
# Summary
# =====================================================
echo "=============================================="
echo "✅ All manifests applied successfully!"
echo "=============================================="
echo ""
echo "=== Pod Status ==="
kubectl get pods -n prod-database -o wide
kubectl get pods -n prod-backend -o wide
kubectl get pods -n prod-staro-modular -o wide
echo ""

echo "=== Services ==="
kubectl get svc -n prod-backend
kubectl get svc -n prod-staro-modular
echo ""

echo "=== Ingress ==="
kubectl get ingress -n prod-staro-modular
echo ""

echo "=== Certificates ==="
kubectl get certificates -n prod-staro-modular
echo ""

echo "Next steps:"
echo "  1. Run migrations: ./scripts/03-migrate.sh"
echo "  2. Verify deployment: ./scripts/04-verify.sh"
echo "  3. Check certificate status: kubectl -n prod-staro-modular describe certificate wildcard-ostechnologies-tls"
