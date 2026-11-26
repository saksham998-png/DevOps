"""Taskboard for Lab 4 (advanced deployments and capstone).

* VERSION / TRACK identify which release served a request (blue/green/stable/canary).
* Secrets come only from mounted files (SECRETS_DIR) or the environment; there are no
  built-in defaults, and they are never returned or logged.
* FAIL_RATE (0.0-1.0) makes a fraction of /api requests return 500, to simulate a bad
  release so canary analysis and rollback can be demonstrated with real metrics.
"""
import hashlib
import hmac
import json
import logging
import os
import random
import socket
import sys
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Counter, Gauge, Histogram, generate_latest

VERSION = os.getenv("APP_VERSION", "dev")
TRACK = os.getenv("TRACK", "stable")
HOST = socket.gethostname()
SECRET_NAMES = ("db_password", "api_key")

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
log = logging.getLogger("taskboard")


def read_secret(name):
    directory = os.getenv("SECRETS_DIR", "/etc/taskboard/secrets")
    path = os.path.join(directory, name)
    if os.path.isfile(path):
        with open(path) as fh:
            return fh.read().strip() or None
    return os.getenv(name.upper()) or None


def fingerprint(value):
    """Non-reversible identifier so operators can tell which secret version is loaded."""
    return "sha256:" + hashlib.sha256(value.encode()).hexdigest()[:8]


class MemoryStore:
    def __init__(self):
        self.tasks, self.next_id = {}, 1

    def ping(self):
        return True

    def all(self):
        return [self.tasks[k] for k in sorted(self.tasks)]

    def add(self, title):
        task = {"id": self.next_id, "title": title}
        self.tasks[self.next_id] = task
        self.next_id += 1
        return task


class RedisStore:
    def __init__(self, host, port, password):
        import redis

        self.r = redis.Redis(host=host, port=port, password=password,
                             decode_responses=True, socket_timeout=2)

    def ping(self):
        try:
            return bool(self.r.ping())
        except Exception:
            return False

    def all(self):
        raw = self.r.hgetall("tasks")
        return [json.loads(raw[k]) for k in sorted(raw, key=int)]

    def add(self, title):
        task = {"id": self.r.incr("task_id"), "title": title}
        self.r.hset("tasks", task["id"], json.dumps(task))
        return task


def create_app(store=None, fail_rate=None):
    app = Flask(__name__)
    if store is None:
        redis_host = os.getenv("REDIS_HOST")
        store = (RedisStore(redis_host, int(os.getenv("REDIS_PORT", "6379")), read_secret("db_password"))
                 if redis_host else MemoryStore())
    if fail_rate is None:
        fail_rate = float(os.getenv("FAIL_RATE", "0"))
    state = {"ready": True}

    registry = CollectorRegistry()
    requests_total = Counter("http_requests_total", "HTTP requests",
                             ["route", "method", "status", "version", "track"], registry=registry)
    latency = Histogram("http_request_duration_seconds", "Request latency", ["route"], registry=registry)
    Gauge("app_info", "Release info", ["version", "track"], registry=registry).labels(VERSION, TRACK).set(1)

    @app.before_request
    def begin():
        g.t0 = time.perf_counter()

    @app.after_request
    def finish(resp):
        route = request.url_rule.rule if request.url_rule else "unmatched"
        if route != "/metrics":
            requests_total.labels(route, request.method, resp.status_code, VERSION, TRACK).inc()
            latency.labels(route).observe(time.perf_counter() - g.t0)
            log.info(json.dumps({"event": "http_request", "path": request.path, "status": resp.status_code,
                                 "version": VERSION, "track": TRACK, "pod": HOST}))
        resp.headers["X-App-Version"] = VERSION
        resp.headers["X-App-Track"] = TRACK
        resp.headers["X-Content-Type-Options"] = "nosniff"
        return resp

    def maybe_fail():
        # simulated defect for canary demos, not a security control
        if fail_rate > 0 and random.random() < fail_rate:  # nosec B311
            return jsonify(error="simulated failure"), 500
        return None

    @app.get("/")
    def index():
        return jsonify(service="taskboard", version=VERSION, track=TRACK, pod=HOST)

    @app.get("/healthz")
    def healthz():
        return jsonify(status="alive")

    @app.get("/readyz")
    def readyz():
        if state["ready"] and store.ping():
            return jsonify(status="ready")
        return jsonify(status="not ready"), 503

    @app.post("/admin/drain")
    def drain():
        token = read_secret("api_key")
        supplied = request.headers.get("Authorization", "")
        if not token or not hmac.compare_digest(supplied, f"Bearer {token}"):
            return jsonify(error="unauthorized"), 401
        state["ready"] = False
        return jsonify(status="draining")

    @app.get("/api/config")
    def config():
        return jsonify(version=VERSION, track=TRACK, secrets={
            name: (fingerprint(v) if (v := read_secret(name)) else "missing") for name in SECRET_NAMES})

    @app.get("/api/tasks")
    def list_tasks():
        return maybe_fail() or jsonify(store.all())

    @app.post("/api/tasks")
    def add_task():
        failed = maybe_fail()
        if failed:
            return failed
        title = str((request.get_json(silent=True) or {}).get("title", "")).strip()
        if not title:
            return jsonify(error="title is required"), 400
        return jsonify(store.add(title)), 201

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)

    return app
