#!/usr/bin/env bash
# =====================================================
# CREATE SECRETS SCRIPT
# Creates Kubernetes secrets from prod.env file
# =====================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${1:-$K8S_DIR/secrets/prod.env}"

echo "=============================================="
echo "STARO MODULAR - CREATE SECRETS"
echo "=============================================="

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Missing env file: $ENV_FILE"
    echo ""
    echo "Create it from the template:"
    echo "  cp $K8S_DIR/secrets/prod.env.template $K8S_DIR/secrets/prod.env"
    echo "  nano $K8S_DIR/secrets/prod.env"
    exit 1
fi

# Load environment variables
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "Loaded environment from: $ENV_FILE"
echo ""

# =====================================================
# Create Namespaces first
# =====================================================
echo "=== Creating Namespaces ==="
kubectl apply -f "$K8S_DIR/namespaces/"
echo ""

# =====================================================
# PostgreSQL Secrets (prod-database)
# =====================================================
echo "=== Creating PostgreSQL Secrets ==="
kubectl -n prod-database delete secret postgres-secrets --ignore-not-found

# Generate postgres exporter DSN
POSTGRES_EXPORTER_DSN="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/postgres?sslmode=disable"

kubectl -n prod-database create secret generic postgres-secrets \
    --from-literal=POSTGRES_DB="${POSTGRES_DB}" \
    --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --from-literal=POSTGRES_EXPORTER_DSN="${POSTGRES_EXPORTER_DSN}"

echo "✓ postgres-secrets created in prod-database"

# =====================================================
# PgBouncer Auth Secret
# =====================================================
echo "=== Creating PgBouncer Auth Secret ==="
# Generate MD5 hash for PgBouncer: md5 + md5(password + username)
PGBOUNCER_MD5=$(echo -n "${POSTGRES_PASSWORD}${POSTGRES_USER}" | md5sum | cut -d' ' -f1)
PGBOUNCER_AUTH="\"${POSTGRES_USER}\" \"md5${PGBOUNCER_MD5}\""

kubectl -n prod-database delete secret pgbouncer-auth --ignore-not-found
kubectl -n prod-database create secret generic pgbouncer-auth \
    --from-literal=userlist.txt="${PGBOUNCER_AUTH}"

echo "✓ pgbouncer-auth created in prod-database"

# =====================================================
# Django Secrets (prod-backend)
# =====================================================
echo "=== Creating Django Secrets ==="
kubectl -n prod-backend delete secret django-secrets --ignore-not-found

# URL-encode the password for DATABASE_URL
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${POSTGRES_PASSWORD}', safe=''))" 2>/dev/null || echo "${POSTGRES_PASSWORD}")
DJANGO_DATABASE_URL="postgresql://${POSTGRES_USER}:${ENCODED_PASSWORD}@pgbouncer.prod-database.svc.cluster.local:5432/${POSTGRES_DB}"

kubectl -n prod-backend create secret generic django-secrets \
    --from-literal=DATABASE_URL="${DJANGO_DATABASE_URL}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --from-literal=SECRET_KEY="${DJANGO_SECRET_KEY}" \
    --from-literal=DEBUG="${DJANGO_DEBUG:-False}" \
    --from-literal=ALLOWED_HOSTS="${DJANGO_ALLOWED_HOSTS}" \
    --from-literal=REDIS_URL="${REDIS_URL}" \
    --from-literal=CELERY_BROKER_URL="${CELERY_BROKER_URL}" \
    --from-literal=CELERY_RESULT_BACKEND="${CELERY_RESULT_BACKEND}" \
    --from-literal=CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:-}" \
    --from-literal=CSRF_TRUSTED_ORIGINS="${CSRF_TRUSTED_ORIGINS:-}" \
    --from-literal=DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-noreply@ostechnologies.info}" \
    --from-literal=EMAIL_HOST="${EMAIL_HOST:-}" \
    --from-literal=EMAIL_PORT="${EMAIL_PORT:-587}" \
    --from-literal=EMAIL_HOST_USER="${EMAIL_HOST_USER:-}" \
    --from-literal=EMAIL_HOST_PASSWORD="${EMAIL_HOST_PASSWORD:-}" \
    --from-literal=EMAIL_USE_TLS="${EMAIL_USE_TLS:-True}" \
    --from-literal=STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-}" \
    --from-literal=STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-}" \
    --from-literal=SENTRY_DSN="${SENTRY_DSN:-}"

echo "✓ django-secrets created in prod-backend"

# =====================================================
# GHCR Pull Secret (both namespaces)
# =====================================================
echo "=== Creating GHCR Pull Secrets ==="
for ns in prod-backend prod-staro-modular; do
    kubectl -n "$ns" delete secret ghcr-secret --ignore-not-found
    kubectl -n "$ns" create secret docker-registry ghcr-secret \
        --docker-server="${GHCR_SERVER}" \
        --docker-username="${GHCR_USERNAME}" \
        --docker-password="${GHCR_TOKEN}"
    echo "✓ ghcr-secret created in $ns"
done

# =====================================================
# Frontend Secrets (prod-staro-modular)
# =====================================================
echo "=== Creating Frontend Secrets ==="
kubectl -n prod-staro-modular delete secret staro-frontend-secrets --ignore-not-found
kubectl -n prod-staro-modular create secret generic staro-frontend-secrets \
    --from-literal=VITE_SUPABASE_URL="${VITE_SUPABASE_URL:-}" \
    --from-literal=VITE_SUPABASE_ANON_KEY="${VITE_SUPABASE_ANON_KEY:-}" \
    --from-literal=SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-}" \
    --from-literal=STRIPE_PUBLISHABLE_KEY="${STRIPE_PUBLISHABLE_KEY:-}" \
    --from-literal=STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-}" \
    --from-literal=STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-}" \
    --from-literal=PAYPAL_CLIENT_ID="${PAYPAL_CLIENT_ID:-}" \
    --from-literal=PAYPAL_SECRET="${PAYPAL_SECRET:-}" \
    --from-literal=DEFAULT_PAYMENT_PROVIDER="${DEFAULT_PAYMENT_PROVIDER:-paypal}"

echo "✓ staro-frontend-secrets created in prod-staro-modular"

# =====================================================
# Cloudflare API Token (kube-system for external-dns, cert-manager for DNS-01)
# =====================================================
echo "=== Creating Cloudflare API Token Secret ==="
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    # For external-dns
    kubectl -n kube-system delete secret cloudflare-api-token --ignore-not-found
    kubectl -n kube-system create secret generic cloudflare-api-token \
        --from-literal=api-token="${CLOUDFLARE_API_TOKEN}"
    echo "✓ cloudflare-api-token created in kube-system"
    
    # For cert-manager ClusterIssuer (DNS-01 challenge)
    kubectl -n cert-manager delete secret cloudflare-api-token --ignore-not-found
    kubectl -n cert-manager create secret generic cloudflare-api-token \
        --from-literal=api-token="${CLOUDFLARE_API_TOKEN}"
    echo "✓ cloudflare-api-token created in cert-manager"
else
    echo "⚠ CLOUDFLARE_API_TOKEN not set, skipping"
fi

# =====================================================
# Grafana Admin Password (observability)
# =====================================================
echo "=== Creating Grafana Secret ==="
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability delete secret grafana-admin --ignore-not-found
kubectl -n observability create secret generic grafana-admin \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD:-admin}"
echo "✓ grafana-admin created in observability"

echo ""
echo "=============================================="
echo "✅ All secrets created successfully!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/02-apply.sh"
echo "  2. Run: ./scripts/03-migrate.sh"
echo "  3. Run: ./scripts/04-verify.sh"
