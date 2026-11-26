#!/usr/bin/env bash
# Disaster-recovery drill with measured RTO and RPO.
#   1. write marker tasks          4. delete the whole lab4 namespace (the "disaster")
#   2. take a Velero backup        5. restore from the backup, wait for the app
#   3. write more tasks after it   6. check which tasks came back
# Tasks written after the backup are lost: that gap is the real RPO.
# Requires Velero installed (velero-setup.sh) and the app deployed in lab4.
set -euo pipefail
NS=lab4
RUN="drill-$(date +%Y%m%d-%H%M%S)"
ts() { date +%s; }

api() {  # api METHOD PATH [JSON] - call the app from inside the cluster
  kubectl -n default run "api-$RANDOM" --rm -i --restart=Never --quiet --image=curlimages/curl:8.11.1 -- \
    curl -s -X "$1" -H 'Content-Type: application/json' ${3:+-d "$3"} "http://taskboard.$NS.svc$2"
}

echo "--> 1. marker data"
api POST /api/tasks "{\"title\":\"$RUN-before-backup\"}"; echo
BEFORE="$(api GET /api/tasks)"; echo "tasks now: $BEFORE"

echo "--> 2. backup"
velero backup create "$RUN" --include-namespaces "$NS" --default-volumes-to-fs-backup --wait
BACKUP_AT=$(ts)
velero backup describe "$RUN" | grep -E "Phase|Items backed up|Started|Completed"

echo "--> 3. write after the backup (this will be lost)"
sleep 20
api POST /api/tasks "{\"title\":\"$RUN-after-backup\"}"; echo
LAST_WRITE_AT=$(ts)

echo "--> 4. DISASTER: deleting namespace $NS"
DISASTER_AT=$(ts)
kubectl delete namespace "$NS" --wait=true
kubectl get ns "$NS" 2>&1 || true

echo "--> 5. restore"
velero restore create "$RUN-restore" --from-backup "$RUN" --wait
kubectl -n "$NS" rollout status deploy/redis --timeout=300s
kubectl -n "$NS" rollout status deploy/taskboard --timeout=300s
RECOVERED_AT=$(ts)

echo "--> 6. verify data"
AFTER="$(api GET /api/tasks)"; echo "tasks after restore: $AFTER"
grep -q "$RUN-before-backup" <<<"$AFTER" && echo "  [ok]   pre-backup task restored" || echo "  [FAIL] pre-backup task missing"
grep -q "$RUN-after-backup"  <<<"$AFTER" && echo "  [?]    post-backup task present" || echo "  [lost] post-backup task (expected: written after the backup)"

echo
echo "===== results for $RUN ====="
echo "RTO (namespace deleted -> app ready): $(( RECOVERED_AT - DISASTER_AT )) s"
echo "RPO (data written after last backup): $(( LAST_WRITE_AT - BACKUP_AT )) s of writes lost"
echo "With the hourly schedule the worst-case RPO is 3600 s."
