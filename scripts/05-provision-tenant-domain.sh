#!/usr/bin/env bash
# =====================================================
# PROVISION TENANT CUSTOM DOMAIN
# Creates ingress and certificate for a tenant's custom domain
# =====================================================
# Usage: ./05-provision-tenant-domain.sh <tenant-slug> <custom-domain> [tenant-uuid]
# Example: ./05-provision-tenant-domain.sh acme-corp www.acme-corp.com
# =====================================================
set -euo pipefail

TENANT_SLUG="${1:?Usage: $0 <tenant-slug> <custom-domain> [tenant-uuid]}"
CUSTOM_DOMAIN="${2:?Usage: $0 <tenant-slug> <custom-domain> [tenant-uuid]}"
TENANT_ID="${3:-}"

echo "=============================================="
echo "STARO MODULAR - PROVISION TENANT DOMAIN"
echo "=============================================="
echo ""
echo "Tenant Slug:    $TENANT_SLUG"
echo "Custom Domain:  $CUSTOM_DOMAIN"
echo ""

# If tenant ID not provided, look it up from Django
if [[ -z "$TENANT_ID" ]]; then
    echo "Looking up tenant ID from Django..."
    TENANT_ID=$(kubectl -n prod-backend exec -it deploy/django-api -- python -c "
from apps.tenancy.models import Tenant
t = Tenant.objects.filter(domains__subdomain='$TENANT_SLUG').first()
if t:
    print(str(t.id))
else:
    t = Tenant.objects.filter(name__iexact='$TENANT_SLUG').first()
    if t:
        print(str(t.id))
" 2>/dev/null | tr -d '\r' || echo "")

    if [[ -z "$TENANT_ID" ]]; then
        echo "❌ Could not find tenant with slug: $TENANT_SLUG"
        echo "   Please provide tenant UUID as third argument"
        exit 1
    fi
fi

echo "Tenant ID:      $TENANT_ID"
echo ""

# =====================================================
# Create Ingress for Custom Domain
# =====================================================
echo "Creating Ingress for custom domain..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tenant-${TENANT_SLUG}-custom
  namespace: prod-staro-modular
  labels:
    app.kubernetes.io/name: staro-modular
    app.kubernetes.io/component: custom-domain
    staro.io/tenant-id: "${TENANT_ID}"
    staro.io/tenant-slug: "${TENANT_SLUG}"
    staro.io/domain-type: "custom"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod-dns
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "120"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/limit-rpm: "300"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/use-forwarded-headers: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - "${CUSTOM_DOMAIN}"
      secretName: tls-${TENANT_SLUG}
  rules:
    - host: "${CUSTOM_DOMAIN}"
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: django-api-svc
                port:
                  number: 8000
          - path: /admin
            pathType: Prefix
            backend:
              service:
                name: django-api
                port:
                  number: 8000
          - path: /media
            pathType: Prefix
            backend:
              service:
                name: django-api-svc
                port:
                  number: 8000
          - path: /health
            pathType: Prefix
            backend:
              service:
                name: staro-modular
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: staro-modular
                port:
                  number: 80
EOF

echo "✓ Ingress created"
echo ""

# =====================================================
# Update Tenant in Django
# =====================================================
echo "Updating tenant domains in Django..."
kubectl -n prod-backend exec -it deploy/django-api -- python manage.py shell -c "
from apps.tenancy.models import Tenant
import json

t = Tenant.objects.get(id='${TENANT_ID}')
domains = t.domains or {}

# Ensure custom_domains is a list
if 'custom_domains' not in domains:
    domains['custom_domains'] = []

# Add the custom domain if not already present
if '${CUSTOM_DOMAIN}' not in domains['custom_domains']:
    domains['custom_domains'].append('${CUSTOM_DOMAIN}')
    t.domains = domains
    t.save()
    print(f'✓ Added {\"${CUSTOM_DOMAIN}\"} to tenant {t.name}')
else:
    print(f'Domain {\"${CUSTOM_DOMAIN}\"} already exists for tenant {t.name}')

print(f'Current domains: {json.dumps(t.domains, indent=2)}')
" 2>/dev/null || echo "⚠ Could not update Django tenant (manual update may be required)"

echo ""

# =====================================================
# Wait for Certificate
# =====================================================
echo "Waiting for TLS certificate to be issued..."
echo "(This may take 1-2 minutes for HTTP-01 challenge)"
echo ""

for i in {1..24}; do
    CERT_READY=$(kubectl -n prod-staro-modular get certificate "tls-${TENANT_SLUG}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
    
    if [[ "$CERT_READY" == "True" ]]; then
        echo "✓ Certificate is ready!"
        break
    elif [[ "$CERT_READY" == "NotFound" ]]; then
        echo "  [$i/24] Certificate not yet created, waiting..."
    else
        echo "  [$i/24] Certificate status: $CERT_READY"
    fi
    
    sleep 5
done

echo ""
echo "=============================================="
echo "✅ Tenant custom domain provisioned!"
echo "=============================================="
echo ""
echo "Domain:       https://${CUSTOM_DOMAIN}"
echo "Tenant ID:    ${TENANT_ID}"
echo "Tenant Slug:  ${TENANT_SLUG}"
echo ""
echo "DNS Configuration Required:"
echo ""
echo "  Add the following DNS records to your domain:"
echo ""
echo "  Type   Name                    Value"
echo "  ─────────────────────────────────────────────────────"
echo "  A      ${CUSTOM_DOMAIN}        <Your-Ingress-External-IP>"
echo "  CNAME  ${CUSTOM_DOMAIN}        ostechnologies.info"
echo ""
echo "  (Choose A record if you have a static IP, CNAME otherwise)"
echo ""
echo "To check certificate status:"
echo "  kubectl -n prod-staro-modular describe certificate tls-${TENANT_SLUG}"
