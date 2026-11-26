#!/usr/bin/env bash
# Installs Vault (dev mode - lab only) and External Secrets Operator, stores freshly
# generated credentials in Vault, and lets only the lab4/vault-reader ServiceAccount read them.
# Requires: kubectl, helm, openssl.
set -euo pipefail

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update >/dev/null

echo "--> installing Vault (dev mode) and External Secrets Operator"
helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
  --set server.dev.enabled=true --set injector.enabled=false --wait
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true --wait

kubectl create namespace lab4 --dry-run=client -o yaml | kubectl apply -f -

vault_exec() { kubectl -n vault exec vault-0 -- "$@"; }

echo "--> writing generated secrets to Vault (values are never printed)"
vault_exec vault secrets enable -path=secret -version=2 kv 2>/dev/null || true
vault_exec vault kv put secret/lab4/taskboard \
  db_password="$(openssl rand -hex 24)" api_key="$(openssl rand -hex 24)" >/dev/null

echo "--> least-privilege policy + kubernetes auth role"
vault_exec sh -c 'vault policy write taskboard-read - <<EOF
path "secret/data/lab4/taskboard" { capabilities = ["read"] }
EOF'
vault_exec vault auth enable kubernetes 2>/dev/null || true
vault_exec sh -c 'vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'
vault_exec vault write auth/kubernetes/role/taskboard \
  bound_service_account_names=vault-reader bound_service_account_namespaces=lab4 \
  policies=taskboard-read ttl=15m

echo "--> syncing into Kubernetes"
kubectl apply -k "$(dirname "$0")"
kubectl -n lab4 wait externalsecret/taskboard-secrets --for=condition=Ready --timeout=90s
kubectl -n lab4 get externalsecret,secret taskboard-secrets
echo "Done. Rotate with: kubectl -n vault exec vault-0 -- vault kv patch secret/lab4/taskboard api_key=\$(openssl rand -hex 24)"
