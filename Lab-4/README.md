# Lab 4: Advanced Deployment Strategies & Capstone

**Student:** Saksham Kumar (2301730151)

The taskboard service, run on Kubernetes with blue-green and canary releases,
GitOps delivery through ArgoCD, secrets in Vault, test-gated CI, and backup,
restore and fault-injection drills that **measure** their results.

## Layout

| Path | Purpose |
|---|---|
| `app/app.py` | Flask API on 8080. Secrets come only from mounted files (no defaults). `FAIL_RATE` simulates a bad release. `/metrics` reports version and track. |
| `tests/` | Unit, integration and security tests; CI fails if coverage drops below 90% |
| `k8s/base/` | Namespace, ConfigMap, ServiceAccount, Redis + PVC (password-protected), Deployment (non-root, read-only filesystem, probes, preStop), Service, HPA, PDB, NetworkPolicy |
| `k8s/overlays/prod/` | What ArgoCD deploys; CI updates the image tag here |
| `k8s/secrets/` | External Secrets `SecretStore` and `ExternalSecret` for Vault, plus `vault-setup.sh` |
| `k8s/blue-green/` | Blue (1.0.0) and green (2.0.0) Deployments, live and preview Services, `switch.sh` |
| `k8s/canary/` | Argo Rollouts `Rollout` (10 → 25 → 50 → 100%), Prometheus `AnalysisTemplate`, NGINX ingress, load generator, `canary-demo.sh` |
| `k8s/monitoring/` | In-namespace Prometheus that labels series with pod track and colour |
| `gitops/` | ArgoCD `Application` (auto-sync, prune, self-heal) and `gitops-demo.sh` |
| `dr/` | Velero + MinIO setup, hourly schedule, `dr-drill.sh` (measured RTO/RPO), `etcd-snapshot.sh`, `chaos-drill.sh` |
| `scripts/` | `build-images.sh`, `create-local-secret.sh`, `verify-local.sh` |
| `../.github/workflows/lab4-pipeline.yml` | tests + SAST + gitleaks + manifest validation → build + Trivy → push to GHCR → bump GitOps tag |
| `Jenkinsfile` | The same quality gates in Jenkins |

## Setup (once)

```bash
minikube start --driver=docker --cpus=4 --memory=8192
minikube addons enable ingress
minikube addons enable metrics-server        # for the HPA
cd Lab-4
bash scripts/build-images.sh                 # 1.0.0, 2.0.0, 2.1.0, latest inside minikube
bash k8s/secrets/vault-setup.sh              # Task 6; or: bash scripts/create-local-secret.sh
kubectl apply -k k8s/base && kubectl apply -k k8s/monitoring
kubectl -n lab4 rollout status deploy/taskboard
```

## Runbook (capture the real output of each step for your report)

| Task | Run | Capture |
|---|---|---|
| 1. Disaster recovery | `bash dr/velero-setup.sh`, `bash dr/dr-drill.sh`, `bash dr/etcd-snapshot.sh`, `bash dr/chaos-drill.sh` | The RTO and RPO printed by the drill, the snapshot status table, failed-request counts per fault |
| 2. Automated testing in CI | Push a change under `Lab-4/`; then push a commit that breaks a test | The green run, the red run blocked before **build**, and the JUnit artifact |
| 3. Blue-green | `kubectl apply -k k8s/blue-green`, then `bash k8s/blue-green/switch.sh` (and again to roll back) | Smoke test through the preview Service, requests and failures during the switch, the final live colour |
| 4. GitOps | `bash gitops/gitops-demo.sh`, then the Git-change steps it prints | `Synced/Healthy`, the manual change being reverted, a commit deployed without `kubectl apply` |
| 5. Strategies report | Compare your own numbers from Tasks 1, 3 and 7 | |
| 6. Secret management | `vault-setup.sh`, then `kubectl -n lab4 get externalsecret`, `curl .../api/config` (fingerprints only), rotate in Vault and watch the fingerprint change, gitleaks job in CI | |
| 7. Canary | Install Argo Rollouts (below), `kubectl apply -k k8s/canary`, `bash k8s/canary/canary-demo.sh` | Healthy 2.0.0 promoted step by step; bad 2.1.0 aborted by the AnalysisRun, with the Prometheus error rate |

Install Argo Rollouts:
```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.7.2/install.yaml
# plugin: https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation
```

### Notes
- `k8s/overlays/prod` pulls `ghcr.io/saksham998-png/taskboard-lab4:<sha>` from GHCR. Make the package
  public after the first CI run, or add an image pull secret.
- Rotating `db_password` also requires restarting Redis (`kubectl -n lab4 rollout restart deploy/redis`), because Redis reads its password at startup.
- Vault runs in dev mode (in memory, root token) because this is a lab. Say so in your report.

## Local checks (no cluster needed)

```bash
cd Lab-4 && pip install -r requirements-dev.txt bandit && bash scripts/verify-local.sh
```
