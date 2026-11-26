#!/usr/bin/env bash
# Q7: default bridge (IP only) vs user-defined bridge (IP + DNS by container name).
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '\n===== %s =====\n' "$*"; }
cleanup() { docker rm -f net-a net-b api client >/dev/null 2>&1 || true; docker network rm lab2-net >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
docker image inspect taskboard:1.0.0 >/dev/null 2>&1 || docker build -t taskboard:1.0.0 .

step "Default bridge"
docker run -d --name net-a alpine:3.20 sleep 600 >/dev/null
docker run -d --name net-b alpine:3.20 sleep 600 >/dev/null
A_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' net-a)"
echo "net-a IP: $A_IP"
docker exec net-b ping -c 2 "$A_IP"
docker exec net-b ping -c 1 net-a || echo ">> name lookup fails on the default bridge"

step "User-defined bridge"
docker network create --subnet 172.28.0.0/16 lab2-net
docker network inspect lab2-net --format 'Subnet {{(index .IPAM.Config 0).Subnet}}'
docker run -d --name api --network lab2-net taskboard:1.0.0 >/dev/null
docker run -d --name client --network lab2-net alpine:3.20 sleep 600 >/dev/null
sleep 3
API_IP="$(docker inspect -f '{{(index .NetworkSettings.Networks "lab2-net").IPAddress}}' api)"
echo "api IP: $API_IP"
docker exec client wget -qO- "http://$API_IP:5000/healthz"; echo
docker exec client wget -qO- "http://api:5000/healthz"; echo
docker exec client nslookup api 127.0.0.11
echo ">> containers on different networks can't see each other:"
docker exec net-b ping -c 1 -W 2 "$API_IP" || echo ">> unreachable, as expected"
