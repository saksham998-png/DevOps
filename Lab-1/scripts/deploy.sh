#!/usr/bin/env bash
# Build the taskboard image, replace the running container, verify /health,
# and roll back to the previous image if the new one never becomes healthy.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="taskboard"
PORT="${PORT:-5000}"
TAG="${BUILD_NUMBER:-local}"
IMAGE="${NAME}:${TAG}"

echo "[deploy] building ${IMAGE}"
docker build -t "${IMAGE}" .

PREVIOUS_IMAGE="$(docker inspect --format '{{.Config.Image}}' "${NAME}" 2>/dev/null || true)"

start_container() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  docker run -d --name "${NAME}" --restart unless-stopped \
    -p "${PORT}:5000" -e APP_VERSION="$1" "$2" >/dev/null
}

wait_healthy() {
  for i in $(seq 1 15); do
    if curl -fsS "http://localhost:${PORT}/health" >/dev/null; then
      return 0
    fi
    echo "[deploy] waiting for /health (${i}/15)"
    sleep 2
  done
  return 1
}

echo "[deploy] starting ${IMAGE} on port ${PORT}"
start_container "${TAG}" "${IMAGE}"

if wait_healthy; then
  echo "[deploy] healthy: $(curl -fsS "http://localhost:${PORT}/health")"
  exit 0
fi

echo "[deploy] new container failed health checks" >&2
docker logs "${NAME}" >&2 || true

if [ -n "${PREVIOUS_IMAGE}" ] && [ "${PREVIOUS_IMAGE}" != "${IMAGE}" ]; then
  echo "[deploy] rolling back to ${PREVIOUS_IMAGE}" >&2
  start_container "rollback" "${PREVIOUS_IMAGE}"
  wait_healthy && echo "[deploy] rollback healthy" >&2
fi
exit 1
