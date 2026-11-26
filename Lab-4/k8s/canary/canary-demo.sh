#!/usr/bin/env bash
# Two real canary releases:
#   1. 2.0.0 healthy   -> analysis passes, traffic goes 10% -> 25% -> 50% -> 100%
#   2. 2.1.0 FAIL_RATE -> 30% of canary requests fail, analysis aborts, traffic returns to stable
# Requires the kubectl-argo-rollouts plugin.
set -euo pipefail
NS=lab4
ROLL="kubectl argo rollouts -n $NS"
PROM_QUERY='sum by (pod_track, status) (rate(http_requests_total{app="taskboard-canary",route=~"/api/.*"}[1m]))'

prom() {
  kubectl -n $NS exec deploy/load-generator -- curl -s --get http://prometheus:9090/api/v1/query \
    --data-urlencode "query=$PROM_QUERY"; echo
}

wait_phase() {  # wait until the rollout reaches one of the given phases
  for _ in $(seq 1 120); do
    phase="$($ROLL status taskboard --timeout 1s 2>/dev/null | tail -1 || true)"
    for want in "$@"; do [[ "$phase" == *"$want"* ]] && { echo "phase: $phase"; return 0; }; done
    sleep 5
  done
  echo "timed out waiting for $*" >&2; return 1
}

echo "===== release 2.0.0 (healthy) ====="
$ROLL set image taskboard taskboard=ghcr.io/saksham998-png/taskboard-lab4:2.0.0
sleep 60; $ROLL get rollout taskboard; prom
wait_phase Healthy
$ROLL get rollout taskboard
kubectl -n $NS get analysisrun

echo "===== release 2.1.0 (bad: FAIL_RATE=0.3) ====="
kubectl -n $NS patch rollout taskboard --type json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"ghcr.io/saksham998-png/taskboard-lab4:2.1.0"},
  {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0.3"}]'
sleep 60; $ROLL get rollout taskboard; prom
wait_phase Degraded Aborted
$ROLL get rollout taskboard
kubectl -n $NS get analysisrun
kubectl -n $NS describe analysisrun | grep -A3 -i "message\|value" | head -30
echo ">> canary aborted; 100% of traffic is back on stable 2.0.0"

echo "Reset with: kubectl -n $NS patch rollout taskboard --type json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/1/value\",\"value\":\"0\"}]'"
