#!/usr/bin/env bash
# Checks everything that doesn't need a cluster: tests + coverage gate, SAST,
# shell syntax and (if kubectl is installed) that every kustomization renders.
set -euo pipefail
cd "$(dirname "$0")/.."
ok() { printf '  [ok] %s\n' "$*"; }

echo "1/4 tests"
python -m pytest -q --cov=app --cov-fail-under=90 && ok "tests and coverage"

echo "2/4 SAST"
if command -v bandit >/dev/null; then bandit -q -r app -ll && ok "bandit"; else echo "  [skip] pip install bandit"; fi

echo "3/4 shell scripts"
for f in scripts/*.sh dr/*.sh gitops/*.sh k8s/*/*.sh; do bash -n "$f"; done && ok "syntax"

echo "4/4 manifests"
if command -v kubectl >/dev/null; then
  for d in base overlays/prod blue-green canary monitoring secrets; do kubectl kustomize "k8s/$d" >/dev/null; done
  ok "kustomize render"
else
  echo "  [skip] kubectl not installed"
fi
