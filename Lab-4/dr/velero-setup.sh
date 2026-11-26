#!/usr/bin/env bash
# Installs MinIO (S3-compatible backup target, in-cluster for the lab) and Velero with
# file-system backup of PVCs, then creates the daily backup schedule.
# Requires: kubectl, velero CLI (https://velero.io/docs/main/basic-install/), openssl.
set -euo pipefail
cd "$(dirname "$0")"

MINIO_USER="velero"
MINIO_PASS="$(openssl rand -hex 16)"   # generated per install, never committed
CREDS="$(mktemp)"; trap 'rm -f "$CREDS"' EXIT

echo "--> MinIO"
kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -
kubectl -n minio create secret generic minio-root \
  --from-literal=user="$MINIO_USER" --from-literal=password="$MINIO_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f minio.yaml
kubectl -n minio rollout restart deploy/minio >/dev/null 2>&1 || true
kubectl -n minio rollout status deploy/minio --timeout=180s
kubectl -n minio wait --for=condition=complete job/minio-make-bucket --timeout=120s

printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' "$MINIO_USER" "$MINIO_PASS" >"$CREDS"

echo "--> Velero"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.11.0 \
  --bucket velero \
  --secret-file "$CREDS" \
  --use-volume-snapshots=false \
  --use-node-agent --default-volumes-to-fs-backup \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.minio.svc:9000 \
  --wait

kubectl apply -f velero-schedule.yaml
velero backup-location get
velero schedule get
