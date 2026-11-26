#!/usr/bin/env bash
# Fault injection with measured impact. Sends a request every 100 ms throughout and
# reports how many failed and how long recovery took for each fault.
#   fault 1: kill an app pod          -> expect 0 failed requests (other replicas serve)
#   fault 2: kill the Redis pod       -> readiness fails, requests fail until Redis is back
#   fault 3: drain one pod via /admin -> pod leaves the Service but isn't restarted
set -euo pipefail
NS=lab4

kubectl -n $NS get pod chaos-probe >/dev/null 2>&1 || \
  kubectl -n $NS run chaos-probe --image=curlimages/curl:8.11.1 --restart=Never --labels=app=taskboard-probe --command -- sleep 7200
kubectl -n $NS wait pod/chaos-probe --for=condition=Ready --timeout=60s >/dev/null

traffic() {  # traffic SECONDS OUTFILE
  kubectl -n $NS exec chaos-probe -- sh -c "end=\$(( \$(date +%s) + $1 )); while [ \$(date +%s) -lt \$end ]; do
    curl -s -o /dev/null -w '%{http_code} ' --max-time 2 http://taskboard/api/tasks; sleep 0.1; done" >"$2"
}
summary() { echo "    requests: $(wc -w <"$1"), failed: $(tr ' ' '\n' <"$1" | grep -cv '^200$' || true)"; }
wait_ready() {  # seconds until deploy has all replicas ready again
  local start=$(date +%s); kubectl -n $NS rollout status "deploy/$1" --timeout=300s >/dev/null
  kubectl -n $NS wait pod -l "app=$1" --for=condition=Ready --timeout=300s >/dev/null; echo $(( $(date +%s) - start ))
}

echo "===== fault 1: kill an app pod ====="
LOG1=$(mktemp); traffic 40 "$LOG1" & T=$!; sleep 5
VICTIM=$(kubectl -n $NS get pod -l app=taskboard -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS delete pod "$VICTIM" --grace-period=0 --force
echo "    replacement ready after $(wait_ready taskboard) s"
wait $T; summary "$LOG1"

echo "===== fault 2: kill Redis (dependency outage) ====="
LOG2=$(mktemp); traffic 60 "$LOG2" & T=$!; sleep 5
kubectl -n $NS delete pod -l app=redis --grace-period=0 --force
echo "    redis ready after $(wait_ready redis) s"
echo "    app ready after another $(wait_ready taskboard) s"
wait $T; summary "$LOG2"
echo "    data still there (PVC + AOF): $(kubectl -n $NS exec chaos-probe -- curl -s http://taskboard/api/tasks | head -c 200)"

echo "===== fault 3: drain one pod ====="
POD=$(kubectl -n $NS get pod -l app=taskboard -o jsonpath='{.items[0].metadata.name}')
KEY=$(kubectl -n $NS get secret taskboard-secrets -o jsonpath='{.data.api_key}' | base64 -d)
kubectl -n $NS exec chaos-probe -- curl -s -X POST -H "Authorization: Bearer $KEY" \
  "http://$(kubectl -n $NS get pod "$POD" -o jsonpath='{.status.podIP}'):8080/admin/drain"; echo
sleep 15
kubectl -n $NS get pod "$POD" -o jsonpath='{.metadata.name} ready={.status.containerStatuses[0].ready} restarts={.status.containerStatuses[0].restartCount}{"\n"}'
kubectl -n $NS get endpoints taskboard
kubectl -n $NS delete pod "$POD"   # bring it back
rm -f "$LOG1" "$LOG2"
