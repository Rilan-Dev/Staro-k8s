#!/usr/bin/env bash
# =====================================================
# DEPLOY WITH ARGOCD
# Sets up GitOps deployment using ArgoCD
# =====================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

REPO_URL="${REPO_URL:-https://github.com/Rilan-Dev/staro_modular-API.git}"

echo "=============================================="
echo "STARO MODULAR - ARGOCD GITOPS SETUP"
echo "=============================================="
echo ""

# =====================================================
# Check if ArgoCD is installed
# =====================================================
if ! kubectl get namespace argocd &>/dev/null; then
    echo "=== Installing ArgoCD ==="
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo "Waiting for ArgoCD to be ready..."
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
    echo ""
fi

# =====================================================
# Get ArgoCD admin password
# =====================================================
echo "=== ArgoCD Admin Credentials ==="
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [[ -n "$ARGOCD_PASSWORD" ]]; then
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
else
    echo "Initial admin secret not found. Password may have been deleted."
    echo "Reset with: kubectl -n argocd patch secret argocd-secret -p '{\"stringData\": {\"admin.password\": \"$(htpasswd -bnBC 10 \"\" newpassword | tr -d ':\n')\"}}'}"
fi
echo ""

# =====================================================
# Create ArgoCD Ingress
# =====================================================
echo "=== Creating ArgoCD Ingress ==="
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - argocd.ostechnologies.info
      secretName: argocd-server-tls
  rules:
    - host: argocd.ostechnologies.info
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
EOF
echo ""

# =====================================================
# Apply ArgoCD Applications
# =====================================================
echo "=== Deploying ArgoCD Applications ==="
kubectl apply -f "$K8S_DIR/argocd/applications.yaml"
echo ""

# =====================================================
# Summary
# =====================================================
echo "=============================================="
echo "✅ ArgoCD GitOps Setup Complete!"
echo "=============================================="
echo ""
echo "Access ArgoCD:"
echo "  URL: https://argocd.ostechnologies.info"
echo "  Username: admin"
if [[ -n "$ARGOCD_PASSWORD" ]]; then
    echo "  Password: $ARGOCD_PASSWORD"
fi
echo ""
echo "Or port-forward for local access:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then access: https://localhost:8080"
echo ""
echo "ArgoCD CLI login:"
echo "  argocd login argocd.ostechnologies.info --username admin --password '$ARGOCD_PASSWORD'"
echo ""
echo "Applications deployed:"
kubectl -n argocd get applications
echo ""
