#!/usr/bin/env bash
# Blue-green cutover with a real downtime measurement.
#   ./switch.sh            -> switch live traffic to the idle colour
#   ./switch.sh rollback   -> same thing; switching back IS the rollback
# While switching, a probe pod sends a request to the live Service every 100 ms and
# every non-200 response is counted, so "zero downtime" is measured, not assumed.
set -euo pipefail
NS=lab4
LOG="$(mktemp)"

live_color() { kubectl -n $NS get svc taskboard-live -o jsonpath='{.spec.selector.color}'; }
set_selector() { kubectl -n $NS patch svc "$1" --type merge -p "{\"spec\":{\"selector\":{\"app\":\"taskboard-bg\",\"color\":\"$2\"}}}" >/dev/null; }
in_cluster() { kubectl -n $NS exec bg-probe -- sh -c "$1"; }

FROM="$(live_color)"
TO=$([ "$FROM" = blue ] && echo green || echo blue)
echo "live is ${FROM}; switching to ${TO}"

echo "--> 1. target deployment must be fully rolled out"
kubectl -n $NS rollout status deploy/taskboard-"$TO" --timeout=120s

echo "--> 2. start probe pod"
kubectl -n $NS get pod bg-probe >/dev/null 2>&1 || \
  kubectl -n $NS run bg-probe --image=curlimages/curl:8.11.1 --restart=Never --labels=app=taskboard-bg-probe --command -- sleep 3600
kubectl -n $NS wait pod/bg-probe --for=condition=Ready --timeout=60s >/dev/null

echo "--> 3. smoke test ${TO} through the preview Service"
in_cluster "curl -fsS http://taskboard-preview/readyz && echo && curl -fsS http://taskboard-preview/"
echo
in_cluster "curl -fsS http://taskboard-preview/" | grep -q "\"track\":\"${TO}\"" \
  || { echo "preview is not serving ${TO}; aborting" >&2; exit 1; }

echo "--> 4. continuous traffic against live while switching"
kubectl -n $NS exec bg-probe -- sh -c \
  'end=$(( $(date +%s) + 20 )); while [ $(date +%s) -lt $end ]; do
     curl -s -o /dev/null -w "%{http_code} " --max-time 2 http://taskboard-live/api/tasks; sleep 0.1; done' >"$LOG" &
TRAFFIC=$!
sleep 5

START=$(date +%s.%N)
set_selector taskboard-live "$TO"
set_selector taskboard-preview "$FROM"
END=$(date +%s.%N)
awk -v s="$START" -v e="$END" 'BEGIN { printf "    selector patched in %.3f s\n", e - s }'

wait $TRAFFIC
TOTAL=$(wc -w <"$LOG"); FAILED=$(tr ' ' '\n' <"$LOG" | grep -cv '^200$' || true)

echo "--> 5. verify"
in_cluster "curl -fsS http://taskboard-live/"; echo
if [ "$(live_color)" != "$TO" ] || ! in_cluster "curl -fsS http://taskboard-live/" | grep -q "\"track\":\"${TO}\""; then
  echo "verification failed - rolling back to ${FROM}" >&2
  set_selector taskboard-live "$FROM"; set_selector taskboard-preview "$TO"
  exit 2
fi
echo "==> live=${TO}, idle=${FROM} (kept running for instant rollback: ./switch.sh rollback)"
echo "==> requests during switch: ${TOTAL}, failed: ${FAILED}"
rm -f "$LOG"
