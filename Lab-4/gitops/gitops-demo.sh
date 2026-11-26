#!/usr/bin/env bash
# Installs ArgoCD, registers the Application, then proves reconciliation:
#   drift  -> manual scale-down is reverted (selfHeal)
#   change -> a commit that changes Git is rolled out without kubectl apply
set -euo pipefail
cd "$(dirname "$0")/.."

echo "--> install ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
echo "admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"

echo "--> register the Application"
kubectl apply -n argocd -f gitops/argocd-application.yaml
for _ in $(seq 1 60); do
  s="$(kubectl -n argocd get application taskboard-lab4 -o jsonpath='{.status.sync.status}/{.status.health.status}')"
  echo "    $s"; [ "$s" = "Synced/Healthy" ] && break; sleep 10
done

echo "--> drift test: change the HPA by hand (minReplicas 3 -> 1)"
kubectl -n lab4 patch hpa taskboard --type merge -p '{"spec":{"minReplicas":1}}'
sleep 5
kubectl -n argocd get application taskboard-lab4 -o jsonpath='{.status.sync.status}{"\n"}'
for _ in $(seq 1 30); do
  m="$(kubectl -n lab4 get hpa taskboard -o jsonpath='{.spec.minReplicas}')"
  echo "    hpa minReplicas=$m"; [ "$m" = "3" ] && { echo ">> ArgoCD reverted the manual change"; break; }; sleep 5
done

cat <<'EOF'

--> Git change test (do this yourself):
    1. edit Lab-4/k8s/base/resources.yaml, e.g. maxReplicas: 8 -> 6
    2. git commit -am "gitops: lower maxReplicas" && git push
    3. watch: kubectl -n argocd get application taskboard-lab4 -w
              kubectl -n lab4 get hpa taskboard -w
EOF
