#!/usr/bin/env bash
# =====================================================
# PREFLIGHT CHECK SCRIPT
# Verifies cluster prerequisites before deployment
# =====================================================
set -euo pipefail

echo "=============================================="
echo "STARO MODULAR - DEPLOYMENT PREFLIGHT CHECK"
echo "=============================================="
echo ""

ERRORS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() { echo -e "${GREEN}✓${NC} $1"; }
check_fail() { echo -e "${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "=== 1. Kubernetes Cluster ==="
if kubectl cluster-info &>/dev/null; then
    check_pass "Cluster is accessible"
    kubectl get nodes -o wide 2>/dev/null | head -5
else
    check_fail "Cannot connect to Kubernetes cluster"
    exit 1
fi
echo ""

echo "=== 2. Required Namespaces ==="
for ns in ingress-nginx cert-manager; do
    if kubectl get ns "$ns" &>/dev/null; then
        check_pass "Namespace '$ns' exists"
    else
        check_fail "Namespace '$ns' NOT FOUND - install required addon"
    fi
done
echo ""

echo "=== 3. Ingress Controller ==="
if kubectl -n ingress-nginx get pods -l app.kubernetes.io/name=ingress-nginx -o name 2>/dev/null | grep -q pod; then
    check_pass "NGINX Ingress Controller is running"
    kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.type}' 2>/dev/null && echo ""
else
    check_fail "NGINX Ingress Controller NOT running"
fi
echo ""

echo "=== 4. Cert-Manager ==="
if kubectl -n cert-manager get pods -l app.kubernetes.io/name=cert-manager -o name 2>/dev/null | grep -q pod; then
    check_pass "Cert-Manager is running"
else
    check_fail "Cert-Manager NOT running"
fi
echo ""

echo "=== 5. IngressClass Check ==="
INGRESS_CLASSES=$(kubectl get ingressclass -o name 2>/dev/null | wc -l)
if [ "$INGRESS_CLASSES" -ge 1 ]; then
    check_pass "IngressClass found:"
    kubectl get ingressclass 2>/dev/null
else
    check_fail "No IngressClass defined"
fi
echo ""

echo "=== 6. Traefik Conflict Check ==="
if kubectl get pods -A 2>/dev/null | grep -qi traefik; then
    check_warn "Traefik pods detected - may conflict with NGINX!"
    echo "    Run: kubectl -n traefik scale deploy/traefik --replicas=0"
else
    check_pass "No Traefik conflict detected"
fi
echo ""

echo "=== 7. Worker Nodes ==="
WORKER_COUNT=$(kubectl get nodes -l nodepool=workers -o name 2>/dev/null | wc -l)
if [ "$WORKER_COUNT" -ge 1 ]; then
    check_pass "Worker nodes with 'nodepool=workers' label: $WORKER_COUNT"
else
    check_warn "No nodes labeled 'nodepool=workers'"
    echo "    Run: kubectl label node <node-name> nodepool=workers"
fi
echo ""

echo "=== 8. Storage Class ==="
if kubectl get storageclass local-storage &>/dev/null; then
    check_pass "StorageClass 'local-storage' exists"
else
    check_warn "StorageClass 'local-storage' not found (will be created during deploy)"
fi
echo ""

echo "=== 9. Port Availability ==="
echo "Checking NodePorts on ingress-nginx-controller..."
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[*]}{.name}: {.nodePort}{"\n"}{end}' 2>/dev/null || echo "Could not determine NodePorts"
echo ""

echo "=== 10. DNS Resolution (from cluster) ==="
if kubectl run dns-test --rm -i --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default &>/dev/null; then
    check_pass "Cluster DNS is working"
else
    check_warn "Could not verify cluster DNS"
fi
echo ""

echo "=============================================="
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}All preflight checks passed!${NC}"
    echo "You can proceed with deployment."
else
    echo -e "${RED}$ERRORS preflight check(s) failed.${NC}"
    echo "Please fix the issues above before deploying."
    exit 1
fi
echo "=============================================="
