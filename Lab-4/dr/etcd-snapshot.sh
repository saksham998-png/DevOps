#!/usr/bin/env bash
# Takes a real etcd snapshot of a Minikube control plane and copies it to ./backups.
# (On kubeadm clusters the same etcdctl flags apply with /etc/kubernetes/pki/etcd/*.)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups

POD="$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')"
CERTS=/var/lib/minikube/certs/etcd
SNAP="/var/lib/minikube/etcd/snapshot-$(date +%Y%m%d-%H%M%S).db"

echo "--> snapshot from $POD"
kubectl -n kube-system exec "$POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=$CERTS/ca.crt --cert=$CERTS/server.crt --key=$CERTS/server.key \
  snapshot save "$SNAP"

echo "--> verify"
kubectl -n kube-system exec "$POD" -- etcdutl snapshot status "$SNAP" -w table

echo "--> copy off the node"
minikube cp "minikube:$SNAP" "backups/$(basename "$SNAP")"
ls -lh backups/

cat <<EOF

Restore procedure (destructive - practice on a throwaway cluster):
  minikube ssh
  sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/      # stop the API server
  sudo etcdutl snapshot restore $SNAP --data-dir /var/lib/minikube/etcd-restored
  sudo sed -i 's#/var/lib/minikube/etcd#/var/lib/minikube/etcd-restored#' /etc/kubernetes/manifests/etcd.yaml
  sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
  # wait for the static pods to restart, then: kubectl get nodes; kubectl get all -A
EOF
