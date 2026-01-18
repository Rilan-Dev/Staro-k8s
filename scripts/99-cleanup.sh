#!/usr/bin/env bash
# =====================================================
# COMPLETE CLEANUP SCRIPT (OPTIONAL)
# Only run this if you want to start fresh!
# =====================================================
# WARNING: This will DELETE all data including database!
# =====================================================
set -euo pipefail

echo "=============================================="
echo "⚠️  STARO MODULAR - COMPLETE CLEANUP"
echo "=============================================="
echo ""
echo "This script will DELETE:"
echo "  - All pods in prod-* namespaces"
echo "  - All PersistentVolumeClaims"
echo "  - All secrets and configmaps"
echo "  - Database data!"
echo ""
read -p "Are you SURE? Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "=== Deleting Deployments ==="

# Delete deployments first (graceful)
kubectl -n prod-backend delete deployment --all --ignore-not-found
kubectl -n prod-staro-modular delete deployment --all --ignore-not-found
kubectl -n prod-database delete statefulset --all --ignore-not-found
kubectl -n prod-database delete deployment --all --ignore-not-found

echo ""
echo "=== Deleting Jobs ==="
kubectl -n prod-backend delete job --all --ignore-not-found

echo ""
echo "=== Deleting Services ==="
kubectl -n prod-backend delete svc --all --ignore-not-found
kubectl -n prod-staro-modular delete svc --all --ignore-not-found
kubectl -n prod-database delete svc --all --ignore-not-found

echo ""
echo "=== Deleting Ingress ==="
kubectl -n prod-staro-modular delete ingress --all --ignore-not-found

echo ""
echo "=== Deleting Secrets and ConfigMaps ==="
# Keep ghcr-secret if you want to avoid re-creating
kubectl -n prod-backend delete secret django-secrets --ignore-not-found
kubectl -n prod-backend delete configmap django-config --ignore-not-found
kubectl -n prod-database delete secret postgres-secrets pgbouncer-auth --ignore-not-found
kubectl -n prod-staro-modular delete secret staro-frontend-secrets --ignore-not-found

echo ""
echo "=== Deleting PVCs ==="
kubectl -n prod-database delete pvc --all --ignore-not-found

echo ""
echo "=== Deleting PVs ==="
kubectl delete pv postgres-pv-worker1 postgres-pv-worker2 redis-pv-worker1 --ignore-not-found

echo ""
echo "=== Deleting Certificates ==="
kubectl -n prod-staro-modular delete certificate --all --ignore-not-found

echo ""
echo "=== Delete HPA/PDB ==="
kubectl -n prod-backend delete hpa --all --ignore-not-found
kubectl -n prod-staro-modular delete hpa --all --ignore-not-found
kubectl -n prod-backend delete pdb --all --ignore-not-found
kubectl -n prod-staro-modular delete pdb --all --ignore-not-found

echo ""
echo "=== Cleanup Home Worker Resources ==="
kubectl -n home-monitoring delete all --all --ignore-not-found 2>/dev/null || true
kubectl delete namespace home-monitoring --ignore-not-found 2>/dev/null || true

echo ""
echo "=============================================="
echo "✅ Cleanup Complete!"
echo "=============================================="
echo ""
echo "Optional: Clean data directories on worker nodes:"
echo "  ssh root@<worker> 'rm -rf /var/lib/k8s-pv/postgres/* /var/lib/k8s-pv/redis/*'"
echo ""
echo "Re-deploy with:"
echo "  ./scripts/01-create-secrets.sh"
echo "  ./scripts/02-apply.sh"
echo "  ./scripts/03-migrate.sh"
