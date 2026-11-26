"""Taskboard for Lab 3: structured JSON logs, Prometheus metrics and a runtime feature flag.

Feature flags are read from FLAGS_FILE (JSON) on every request, falling back to
FEATURE_<NAME> environment variables, so a flag can be flipped without a rebuild or restart.
"""
import json
import logging
import os
import sys
import time
import uuid
from itertools import count

from flask import Flask, Response, g, jsonify, render_template, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Counter, Gauge, Histogram, generate_latest

SERVICE = "taskboard"
VERSION = os.getenv("APP_VERSION", "3.0.0")
FLAGS = ("priority_tasks",)


class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "@timestamp": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + f".{int(record.msecs):03d}Z",
            "level": record.levelname,
            "service": SERVICE,
            "message": record.getMessage(),
        }
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)


class StdoutHandler(logging.StreamHandler):
    """Always write to the current sys.stdout (it can be swapped by test runners/servers)."""

    def emit(self, record):
        self.stream = sys.stdout
        super().emit(record)


def make_logger():
    logger = logging.getLogger(SERVICE)
    if not logger.handlers:
        handler = StdoutHandler()
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))
        logger.propagate = False
    return logger


def flag_enabled(name):
    path = os.getenv("FLAGS_FILE")
    if path and os.path.exists(path):
        try:
            with open(path) as fh:
                data = json.load(fh)
            if name in data:
                return bool(data[name])
        except (OSError, ValueError):
            pass
    return os.getenv(f"FEATURE_{name.upper()}", "false").lower() in ("1", "true", "yes", "on")


def create_app():
    app = Flask(__name__)
    log = make_logger()
    registry = CollectorRegistry()
    requests_total = Counter("taskboard_http_requests_total", "HTTP requests",
                             ["method", "route", "status"], registry=registry)
    latency = Histogram("taskboard_http_request_duration_seconds", "Request latency",
                        ["route"], registry=registry)
    tasks_gauge = Gauge("taskboard_tasks", "Tasks currently stored", registry=registry)
    flag_gauge = Gauge("taskboard_feature_flag_enabled", "Feature flag state (1=on)",
                       ["flag"], registry=registry)
    tasks, ids = {}, count(1)

    def refresh_flags():
        for name in FLAGS:
            flag_gauge.labels(flag=name).set(1 if flag_enabled(name) else 0)

    @app.before_request
    def start():
        g.start = time.perf_counter()
        g.request_id = request.headers.get("X-Request-ID", uuid.uuid4().hex[:12])

    @app.after_request
    def finish(response):
        route = request.url_rule.rule if request.url_rule else "unmatched"
        elapsed = time.perf_counter() - g.start
        if route != "/metrics":
            requests_total.labels(request.method, route, response.status_code).inc()
            latency.labels(route).observe(elapsed)
            log.info("request", extra={"fields": {
                "event": "http_request", "request_id": g.request_id, "method": request.method,
                "path": request.path, "status": response.status_code,
                "duration_ms": round(elapsed * 1000, 2), "client_ip": request.remote_addr,
            }})
        response.headers["X-Request-ID"] = g.request_id
        return response

    def ordered():
        items = list(tasks.values())
        if flag_enabled("priority_tasks"):
            items.sort(key=lambda t: (-t.get("priority", 0), t["id"]))
            return items
        return [{k: v for k, v in t.items() if k != "priority"} for t in items]

    @app.get("/")
    def home():
        return render_template("index.html", version=VERSION, tasks=ordered(),
                               priority=flag_enabled("priority_tasks"))

    @app.get("/health")
    def health():
        return jsonify(status="UP", version=VERSION)

    @app.get("/api/flags")
    def flags():
        return jsonify({name: flag_enabled(name) for name in FLAGS})

    @app.get("/api/tasks")
    def list_tasks():
        return jsonify(ordered())

    @app.post("/api/tasks")
    def create_task():
        body = request.get_json(silent=True) or {}
        title = str(body.get("title", "")).strip()
        if not title:
            log.warning("validation failed", extra={"fields": {"event": "task_rejected"}})
            return jsonify(error="title is required"), 400
        task = {"id": next(ids), "title": title, "done": False}
        if flag_enabled("priority_tasks"):
            try:
                task["priority"] = max(0, min(5, int(body.get("priority", 0))))
            except (TypeError, ValueError):
                return jsonify(error="priority must be an integer 0-5"), 400
        tasks[task["id"]] = task
        tasks_gauge.set(len(tasks))
        log.info("task created", extra={"fields": {"event": "task_created", "task_id": task["id"]}})
        return jsonify(task), 201

    @app.get("/metrics")
    def metrics():
        refresh_flags()
        return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)

    return app


if __name__ == "__main__":
    # dev server only; containers use gunicorn (see Dockerfile)
    create_app().run(host=os.getenv("HOST", "127.0.0.1"), port=int(os.getenv("PORT", "8000")))
