# Lab 2: Containerization & Kubernetes Orchestration

**Student:** Saksham Kumar (2301730151)

The taskboard service, now stored in Redis, containerized with a multi-stage Dockerfile,
run with Docker Compose, and deployed to Minikube.

## Layout

| Path | Purpose |
|---|---|
| `app/app.py` | Flask API: `/`, `/healthz` (liveness), `/readyz` (readiness, checks Redis), `/api/tasks` |
| `Dockerfile` | Multi-stage, `python:3.12-slim`, non-root UID 10001, version set with `--build-arg APP_VERSION` |
| `compose/docker-compose.yml` | `web` + `redis`, named volume, custom bridge network, health-gated startup |
| `k8s/` | Namespace, ConfigMap, Redis + PVC, 3-replica Deployment (rolling update, probes, limits), NodePort Service, Kustomization |
| `scripts/k8s-rollout-demo.sh` | Q1 and Q2: deploy, scale, rolling update, broken release, rollback |
| `scripts/storage-demo.sh` | Q6: container layer vs named volume vs bind mount |
| `scripts/network-demo.sh` | Q7: default bridge vs user-defined bridge and DNS |
| `../.github/workflows/lab2-cd.yml` | Q8: test → build and push to GHCR → deploy to the cluster with automatic rollback |

## Runbook

Prerequisites: Docker, Minikube, kubectl (`minikube start --driver=docker`).

| Question | What to run | What to capture |
|---|---|---|
| Q4 Containerize | `docker build -t taskboard:1.0.0 .` then `docker history taskboard:1.0.0`, `docker run -d -p 5000:5000 --name tb taskboard:1.0.0`, `curl localhost:5000/healthz`, `docker images taskboard` | Build output, layers, image size, running container |
| Q5 Manage containers and Compose | `docker ps`, `docker stop/start/restart/logs tb`, `docker tag taskboard:1.0.0 <dockerhub-user>/taskboard:1.0.0`, `docker push ...`, `docker compose -f compose/docker-compose.yml up -d --build`, `docker compose ps`, POST then GET `/api/tasks` | Lifecycle commands, registry push, both services healthy |
| Q6 Storage | `bash scripts/storage-demo.sh` | The lost file, the surviving volume file, the bind-mount file, tasks surviving `compose down` |
| Q7 Networking | `bash scripts/network-demo.sh` | Ping by IP works but by name fails on the default bridge; DNS works on `lab2-net` |
| Q1 Deploy to Kubernetes | First part of `bash scripts/k8s-rollout-demo.sh` | `get pods,svc,endpoints`, responses from different pods (`pod` field) |
| Q2 Rolling update, rollback, scaling | Rest of the same script | Pods during scaling, ReplicaSets, stalled broken rollout, `rollout history` |
| Q8 CD to Kubernetes | Push a change under `Lab-2/`; see notes below | The Actions run, image in GHCR, pods running the new SHA tag |
| Q3 and Q9 Reports | Use your own captured output from above | |

### Q8 setup

1. The `test` and `build-and-push` jobs work immediately. The image is published at
   `ghcr.io/saksham998-png/taskboard`. Make the package **public** (GitHub → Packages → taskboard →
   Settings), or Minikube won't be able to pull it.
2. To deploy, install a GitHub **self-hosted runner** on the machine running Minikube (repo → Settings → Actions → Runners)
   with `kubectl` and `kustomize` on its PATH. Then set the repository variable `LAB2_DEPLOY=true`.
3. Push a change and capture the run. To show automatic rollback, push a commit that breaks `/readyz`.
