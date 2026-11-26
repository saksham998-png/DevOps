#!/usr/bin/env bash
# Q1 + Q2: deploy to Minikube, scale, rolling update to 2.0.0, break a release, roll back.
# Run from Lab-2/ with minikube already started.  Each step prints real cluster state.
set -euo pipefail
cd "$(dirname "$0")/.."
NS=lab2
step() { printf '\n===== %s =====\n' "$*"; }

step "Build images inside minikube's Docker daemon"
eval "$(minikube docker-env)"
docker build -t taskboard:1.0.0 --build-arg APP_VERSION=1.0.0 .
docker build -t taskboard:2.0.0 --build-arg APP_VERSION=2.0.0 .

step "Apply manifests"
kubectl apply -k k8s/
kubectl -n $NS rollout status deploy/redis --timeout=120s
kubectl -n $NS rollout status deploy/taskboard --timeout=120s
kubectl -n $NS get pods,svc,endpoints -o wide

URL="$(minikube service taskboard -n $NS --url)"
step "Call the service via NodePort: $URL"
for i in 1 2 3 4; do curl -s "$URL/"; echo; done
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"from minikube"}' "$URL/api/tasks"; echo

step "Scale 3 -> 5 -> 2 -> 3"
for n in 5 2 3; do
  kubectl -n $NS scale deploy/taskboard --replicas=$n
  kubectl -n $NS rollout status deploy/taskboard --timeout=120s
  kubectl -n $NS get pods -l app=taskboard
done

step "Rolling update to 2.0.0"
kubectl -n $NS set image deploy/taskboard taskboard=taskboard:2.0.0
kubectl -n $NS annotate deploy/taskboard kubernetes.io/change-cause="upgrade to 2.0.0" --overwrite
kubectl -n $NS rollout status deploy/taskboard --timeout=120s
kubectl -n $NS get rs -l app=taskboard
curl -s "$URL/"; echo

step "Deploy a broken tag (image does not exist)"
kubectl -n $NS set image deploy/taskboard taskboard=taskboard:9.9.9-broken
kubectl -n $NS annotate deploy/taskboard kubernetes.io/change-cause="broken release" --overwrite
kubectl -n $NS rollout status deploy/taskboard --timeout=40s || echo ">> rollout stalled as expected"
kubectl -n $NS get pods -l app=taskboard
echo ">> old pods still serving thanks to maxUnavailable: 0:"
curl -s "$URL/"; echo

step "Roll back"
kubectl -n $NS rollout undo deploy/taskboard
kubectl -n $NS rollout status deploy/taskboard --timeout=120s
kubectl -n $NS rollout history deploy/taskboard
curl -s "$URL/"; echo
