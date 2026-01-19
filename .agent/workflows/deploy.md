---
description: How to deploy Staro Modular to a fresh Kubernetes cluster
---

# Fresh Deployment Workflow

This workflow covers deploying the Staro Modular platform from scratch.

## Prerequisites

1. Kubernetes cluster with 2+ nodes (all in same datacenter for low latency)
2. kubectl configured with cluster access
3. Helm 3.12+ installed
4. Node labels configured:
```bash
kubectl label node <db-node> location=vps nodepool=workers role=database
kubectl label node <worker-node> location=vps nodepool=workers
```

## Deployment Steps

// turbo-all

### Step 1: Clone and Configure
```bash
cd /home/techadmin/k8s
git clone <repo-url> staro-k8s
cd staro-k8s
cp database/prod.env.template database/prod.env
# Edit prod.env with your values
```

### Step 2: Create Namespaces
```bash
kubectl apply -f namespaces/production.yaml
```

### Step 3: Create Secrets
```bash
./scripts/01-create-secrets.sh
```

### Step 4: Deploy Database Layer
```bash
kubectl apply -f database/local-storageclass.yaml
kubectl apply -f database/postgres-pv.yaml
kubectl apply -f database/postgres-statefulset.yaml
kubectl rollout status statefulset/postgres -n prod-database
kubectl apply -f database/pgbouncer.yaml
kubectl rollout status deployment/pgbouncer -n prod-database
```

### Step 5: Deploy Backend
```bash
kubectl apply -f backend/redis.yaml
kubectl apply -f backend/django-rbac.yaml
kubectl apply -f backend/django-migrate-job.yaml
kubectl wait --for=condition=complete job/django-migrate -n prod-backend --timeout=300s
kubectl apply -f backend/django-deployment.yaml
kubectl apply -f backend/celery.yaml
```

### Step 6: Deploy Frontend & Ingress
```bash
kubectl apply -f frontend/staro-deployment.yaml
kubectl apply -f ingress/multi-tenant-ingress.yaml
```

### Step 7: Deploy Observability
```bash
./scripts/06-deploy-observability.sh
```

### Step 8: Verify Deployment
```bash
kubectl get pods -A
./scripts/04-verify.sh
```

## Post-Deployment Checklist

- [ ] All pods running
- [ ] Ingress returning 200
- [ ] Grafana accessible
- [ ] Prometheus targets all UP
- [ ] API response time <500ms

## Troubleshooting

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for detailed troubleshooting.
