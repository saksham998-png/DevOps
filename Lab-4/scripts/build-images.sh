#!/usr/bin/env bash
# Builds the release images straight into Minikube's Docker daemon so the cluster
# can use them without a registry. 2.1.0 is the same code; the canary demo turns on FAIL_RATE.
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(minikube docker-env)"
for v in 1.0.0 2.0.0 2.1.0 latest; do
  docker build --build-arg APP_VERSION="$v" -t "ghcr.io/saksham998-png/taskboard-lab4:$v" .
done
docker images ghcr.io/saksham998-png/taskboard-lab4
