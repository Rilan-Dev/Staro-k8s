#!/usr/bin/env bash
# =====================================================
# DEPLOY OBSERVABILITY STACK
# Installs Prometheus, Grafana, and Loki using Helm
# =====================================================
set -euo pipefail

# Resolve absolute path
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# K8S_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="/home/techadmin/k8s/staro-k8s"

echo "=============================================="
echo "STARO MODULAR - DEPLOY OBSERVABILITY STACK"
echo "=============================================="
echo ""

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first:"
    echo "   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

echo "=== Adding Helm Repositories ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
echo ""

# Create namespace
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# =====================================================
# Prometheus Stack (Prometheus, Alertmanager, Grafana)
# =====================================================
echo "=== Deploying Prometheus Stack ==="

# Get Grafana password from secret or environment
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-admin}"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace observability \
    --values "$K8S_DIR/observability/prometheus-values.yaml" \
    --set grafana.adminPassword="$GRAFANA_PASS" \
    --set alertmanager.config.global.slack_api_url="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/placeholder}" \
    --timeout 10m \
    --wait \
    --debug \
    --v=5

echo "✓ Prometheus Stack deployed"
echo ""

# =====================================================
# Loki Stack (Loki + Promtail)
# =====================================================
echo "=== Deploying Loki Stack ==="

helm upgrade --install loki grafana/loki-stack \
    --namespace observability \
    --values "$K8S_DIR/observability/loki-values.yaml" \
    --timeout 10m \
    --wait \
    --debug \
    --v=5

echo "✓ Loki Stack deployed"
echo ""

# =====================================================
# Apply ServiceMonitors
# =====================================================
echo "=== Applying ServiceMonitors ==="
kubectl apply -f "$K8S_DIR/observability/service-monitors.yaml"
echo ""

# =====================================================
# Summary
# =====================================================
echo "=============================================="
echo "✅ Observability Stack Deployed!"
echo "=============================================="
echo ""
echo "Access URLs:"
echo ""

# Get ingress IPs
GRAFANA_HOST=$(kubectl -n observability get ingress kube-prometheus-stack-grafana -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "grafana.ostechnologies.info")
PROMETHEUS_HOST=$(kubectl -n observability get ingress kube-prometheus-stack-prometheus -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "prometheus.ostechnologies.info")
ALERTMANAGER_HOST=$(kubectl -n observability get ingress kube-prometheus-stack-alertmanager -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "alertmanager.ostechnologies.info")

echo "  Grafana:       https://$GRAFANA_HOST"
echo "  Prometheus:    https://$PROMETHEUS_HOST"
echo "  Alertmanager:  https://$ALERTMANAGER_HOST"
echo ""
echo "Grafana Credentials:"
echo "  Username: admin"
echo "  Password: (from GRAFANA_ADMIN_PASSWORD or 'admin')"
echo ""
echo "Port-forward for local access:"
echo "  kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "  kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
