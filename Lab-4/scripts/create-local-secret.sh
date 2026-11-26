#!/usr/bin/env bash
# Quick alternative to Vault for local runs: create taskboard-secrets with random values
# directly in the cluster. Nothing is written to disk or Git.
set -euo pipefail
kubectl create namespace lab4 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab4 create secret generic taskboard-secrets \
  --from-literal=db_password="$(openssl rand -hex 24)" \
  --from-literal=api_key="$(openssl rand -hex 24)" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "taskboard-secrets created in namespace lab4"
