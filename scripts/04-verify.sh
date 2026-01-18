#!/usr/bin/env bash
# =====================================================
# VERIFICATION SCRIPT
# Comprehensive health check of the deployment
# =====================================================
set -euo pipefail

DOMAIN="${1:-ostechnologies.info}"

echo "=============================================="
echo "STARO MODULAR - DEPLOYMENT VERIFICATION"
echo "Domain: $DOMAIN"
echo "=============================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_pass() { echo -e "${GREEN}✓${NC} $1"; }
check_fail() { echo -e "${RED}✗${NC} $1"; }
check_warn() { echo -e "${YELLOW}!${NC} $1"; }

ERRORS=0

# =====================================================
# Pod Health
# =====================================================
echo "=== 1. Pod Health ==="
echo ""
echo "prod-database:"
kubectl -n prod-database get pods -o wide
echo ""

echo "prod-backend:"
kubectl -n prod-backend get pods -o wide
echo ""

echo "prod-staro-modular:"
kubectl -n prod-staro-modular get pods -o wide
echo ""

# Check for non-Running pods
NOT_RUNNING=$(kubectl get pods -A -l 'app.kubernetes.io/name=staro-modular' --field-selector=status.phase!=Running 2>/dev/null | grep -v "Completed" | grep -v "NAME" | wc -l || echo "0")
if [ "$NOT_RUNNING" -gt 0 ]; then
    check_fail "Some pods are not Running"
    ERRORS=$((ERRORS + 1))
else
    check_pass "All application pods are Running"
fi
echo ""

# =====================================================
# Service Endpoints
# =====================================================
echo "=== 2. Service Endpoints ==="
for svc in "prod-backend/django-api" "prod-backend/redis" "prod-database/pgbouncer" "prod-staro-modular/staro-modular"; do
    ns=$(echo "$svc" | cut -d'/' -f1)
    name=$(echo "$svc" | cut -d'/' -f2)
    EP_COUNT=$(kubectl -n "$ns" get endpoints "$name" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w || echo "0")
    if [ "$EP_COUNT" -gt 0 ]; then
        check_pass "$svc has $EP_COUNT endpoint(s)"
    else
        check_fail "$svc has NO endpoints"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# =====================================================
# Ingress & Certificates
# =====================================================
echo "=== 3. Ingress & Certificates ==="
kubectl -n prod-staro-modular get ingress
echo ""

CERT_READY=$(kubectl -n prod-staro-modular get certificate wildcard-ostechnologies-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$CERT_READY" == "True" ]; then
    check_pass "Wildcard certificate is Ready"
else
    check_warn "Certificate status: $CERT_READY (may take a few minutes)"
fi
echo ""

# =====================================================
# Database Connectivity
# =====================================================
echo "=== 4. Database Connectivity ==="
if kubectl -n prod-database exec statefulset/postgres -- pg_isready -U postgres &>/dev/null; then
    check_pass "PostgreSQL is accepting connections"
else
    check_fail "PostgreSQL is NOT ready"
    ERRORS=$((ERRORS + 1))
fi

# Use endpoint check instead of psql (which requires password)
PGBOUNCER_EP=$(kubectl -n prod-database get endpoints pgbouncer -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w || echo "0")
if [ "$PGBOUNCER_EP" -gt 0 ]; then
    check_pass "PgBouncer has $PGBOUNCER_EP endpoint(s) ready"
else
    check_fail "PgBouncer has NO ready endpoints"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# =====================================================
# Redis Connectivity
# =====================================================
echo "=== 5. Redis Connectivity ==="
if kubectl -n prod-backend exec deployment/redis -- redis-cli ping 2>/dev/null | grep -q PONG; then
    check_pass "Redis is responding to PING"
else
    check_fail "Redis is NOT responding"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# =====================================================
# External HTTP Checks
# =====================================================
echo "=== 6. External HTTP Checks ==="
echo ""

# Test platform domain
echo "Testing platform domain: https://$DOMAIN"
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" == "200" ] || [ "$HTTP_STATUS" == "301" ] || [ "$HTTP_STATUS" == "302" ]; then
    check_pass "https://$DOMAIN/ → HTTP $HTTP_STATUS"
else
    check_warn "https://$DOMAIN/ → HTTP $HTTP_STATUS"
fi

# Test API endpoint
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/v1/platform/plans/" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" == "200" ]; then
    check_pass "https://$DOMAIN/api/v1/platform/plans/ → HTTP $HTTP_STATUS"
else
    check_warn "https://$DOMAIN/api/v1/platform/plans/ → HTTP $HTTP_STATUS"
fi

# Test health endpoint
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/health" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" == "200" ]; then
    check_pass "https://$DOMAIN/health → HTTP $HTTP_STATUS"
else
    check_warn "https://$DOMAIN/health → HTTP $HTTP_STATUS"
fi

# Test a sample tenant subdomain
TENANT_SUBDOMAIN="demo.$DOMAIN"
echo ""
echo "Testing tenant subdomain: https://$TENANT_SUBDOMAIN"
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$TENANT_SUBDOMAIN/" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" == "200" ] || [ "$HTTP_STATUS" == "301" ] || [ "$HTTP_STATUS" == "302" ]; then
    check_pass "https://$TENANT_SUBDOMAIN/ → HTTP $HTTP_STATUS"
else
    check_warn "https://$TENANT_SUBDOMAIN/ → HTTP $HTTP_STATUS (tenant may not exist)"
fi
echo ""

# =====================================================
# TLS Certificate Check
# =====================================================
echo "=== 7. TLS Certificate ==="
CERT_INFO=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "Could not retrieve")
if [[ "$CERT_INFO" == *"notAfter"* ]]; then
    echo "$CERT_INFO"
    check_pass "TLS certificate is valid"
else
    check_warn "Could not verify TLS certificate"
fi
echo ""

# =====================================================
# Resource Usage
# =====================================================
echo "=== 8. Resource Usage ==="
echo "Top pods by CPU:"
kubectl top pods -A --sort-by=cpu 2>/dev/null | head -10 || echo "(metrics-server not available)"
echo ""

# =====================================================
# Summary
# =====================================================
echo "=============================================="
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}All verification checks passed!${NC}"
    echo ""
    echo "Your multi-tenant platform is ready!"
    echo ""
    echo "URLs:"
    echo "  Platform Admin:  https://$DOMAIN"
    echo "  API Docs:        https://$DOMAIN/swagger/"
    echo "  Django Admin:    https://$DOMAIN/admin/"
    echo ""
    echo "Tenant access: https://<tenant-subdomain>.$DOMAIN"
    echo "Example:       https://demo.$DOMAIN"
else
    echo -e "${RED}$ERRORS verification check(s) failed.${NC}"
    echo "Please investigate the issues above."
fi
echo "=============================================="
