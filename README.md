# Staro Modular - Multi-Tenant Kubernetes Configuration
# =====================================================
# 
# This directory contains production-grade Kubernetes manifests
# for deploying the Staro Modular multi-tenant SaaS platform.
#
# ## Directory Structure
#
# ```
# k8s/
# ├── namespaces/          # Namespace definitions
# ├── database/            # PostgreSQL, PgBouncer
# ├── backend/             # Django API, Celery, Redis
# ├── frontend/            # React/Vite frontend
# ├── ingress/             # Ingress rules, certificates
# ├── network/             # Network policies
# ├── policies/            # Resource quotas, limits
# ├── external-dns/        # Automatic DNS management
# ├── observability/       # Prometheus, Loki, Grafana
# ├── argocd/              # GitOps configuration
# ├── lb/                  # HAProxy load balancer
# ├── scripts/             # Deployment scripts
# └── secrets/             # Secret templates (NOT committed)
# ```
#
# ## Quick Start
#
# 1. Copy and configure secrets:
#    ```bash
#    cp secrets/prod.env.template secrets/prod.env
#    nano secrets/prod.env  # Edit with your values
#    ```
#
# 2. Run preflight checks:
#    ```bash
#    ./scripts/00-preflight.sh
#    ```
#
# 3. Create secrets:
#    ```bash
#    ./scripts/01-create-secrets.sh
#    ```
#
# 4. Deploy everything:
#    ```bash
#    ./scripts/02-apply.sh
#    ```
#
# 5. Run migrations:
#    ```bash
#    ./scripts/03-migrate.sh
#    ```
#
# 6. Verify:
#    ```bash
#    ./scripts/04-verify.sh
#    ```
#
# ## Domain Structure
#
# - `ostechnologies.info` → Platform admin / landing page
# - `*.ostechnologies.info` → Tenant subdomains
# - Custom domains → Per-tenant (provisioned via script)
#
# ## Security Notice
#
# - Never commit `secrets/prod.env` to git
# - Use sealed-secrets or external-secrets in production
# - All secrets are created via `01-create-secrets.sh`
#
# 
# # Create the secret in kube-system namespace
# kubectl -n kube-system create secret generic cloudflare-api-token \
# --from-literal=api-token="YOUR_CLOUDFLARE_API_TOKEN_HERE"
#
=====================================================
# Staro-k8s
