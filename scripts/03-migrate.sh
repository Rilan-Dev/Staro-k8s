#!/usr/bin/env bash
# =====================================================
# RUN MIGRATIONS SCRIPT
# Executes Django database migrations
# =====================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "STARO MODULAR - DATABASE MIGRATIONS"
echo "=============================================="
echo ""

# Delete existing job if any
echo "Cleaning up previous migration job..."
kubectl -n prod-backend delete job django-migrate --ignore-not-found
sleep 2

# Apply the migration job
echo "Starting migration job..."
kubectl apply -f "$K8S_DIR/backend/django-migrate-job.yaml"

# Wait for pod to be created
echo "Waiting for migration pod to be created..."
sleep 5

# Get the pod name
POD_NAME=$(kubectl -n prod-backend get pods -l app=django-migrate --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")

if [[ -z "$POD_NAME" ]]; then
    echo "Migration pod not found, waiting..."
    sleep 10
    POD_NAME=$(kubectl -n prod-backend get pods -l app=django-migrate --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
fi

if [[ -n "$POD_NAME" ]]; then
    echo "Following migration logs for pod: $POD_NAME"
    echo "=============================================="
    kubectl -n prod-backend logs -f "$POD_NAME" --container=migrate 2>/dev/null || \
    kubectl -n prod-backend logs -f job/django-migrate --tail=500 || true
else
    echo "Could not find migration pod, checking job status..."
    kubectl -n prod-backend describe job django-migrate
fi

echo ""
echo "=============================================="
echo "Migration job status:"
kubectl -n prod-backend get job django-migrate -o wide
echo "=============================================="

# Check if job succeeded
JOB_STATUS=$(kubectl -n prod-backend get job django-migrate -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
if [[ "$JOB_STATUS" == "1" ]]; then
    echo "✅ Migrations completed successfully!"
else
    JOB_FAILED=$(kubectl -n prod-backend get job django-migrate -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    if [[ "$JOB_FAILED" != "0" ]]; then
        echo "❌ Migration job failed!"
        echo "Check logs with: kubectl -n prod-backend logs job/django-migrate"
        exit 1
    else
        echo "⏳ Migration job still running or in unknown state"
    fi
fi
