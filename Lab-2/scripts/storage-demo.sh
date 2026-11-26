#!/usr/bin/env bash
# Q6: container layer vs named volume vs bind mount.
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '\n===== %s =====\n' "$*"; }
cleanup() { docker rm -f lab2-scratch lab2-scratch2 lab2-bind >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

step "1. Writable container layer is lost with the container"
docker run -d --name lab2-scratch alpine:3.20 sleep 600 >/dev/null
docker exec lab2-scratch sh -c 'echo "written at $(date)" > /tmp/note.txt && cat /tmp/note.txt'
docker rm -f lab2-scratch >/dev/null
docker run -d --name lab2-scratch2 alpine:3.20 sleep 600 >/dev/null
docker exec lab2-scratch2 cat /tmp/note.txt || echo ">> file is gone"

step "2. Named volume survives container removal"
docker volume create lab2-vol >/dev/null
docker run --rm -v lab2-vol:/data alpine:3.20 sh -c 'echo "saved at $(date)" > /data/note.txt'
docker run --rm -v lab2-vol:/data alpine:3.20 cat /data/note.txt
docker volume inspect lab2-vol --format 'Mountpoint: {{ .Mountpoint }}'

step "3. Bind mount shares a host folder both ways"
HOSTDIR="$(pwd)/bind-demo"
mkdir -p "$HOSTDIR" && echo "from host" > "$HOSTDIR/shared.txt"
docker run -d --name lab2-bind -v "$HOSTDIR":/shared alpine:3.20 sleep 600 >/dev/null
docker exec lab2-bind cat /shared/shared.txt
docker exec lab2-bind sh -c 'echo "from container" >> /shared/shared.txt'
docker rm -f lab2-bind >/dev/null
echo ">> host copy after container removed:"; cat "$HOSTDIR/shared.txt"

step "4. Compose: tasks persist across 'down' because Redis uses a named volume"
docker compose -f compose/docker-compose.yml up -d --build --wait
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"persist me"}' localhost:5000/api/tasks; echo
docker compose -f compose/docker-compose.yml down          # no -v: keeps redis-data
docker compose -f compose/docker-compose.yml up -d --wait
curl -s localhost:5000/api/tasks; echo
docker compose -f compose/docker-compose.yml down

echo; echo "Clean up afterwards with: docker volume rm lab2-vol lab2_redis-data && rm -rf bind-demo"
