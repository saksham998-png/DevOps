"""Taskboard for Lab 2: same API as Lab 1, but tasks live in Redis so they survive
container restarts and are shared by every replica behind a Service."""
import json
import os
import socket

from flask import Flask, jsonify, request

VERSION = os.getenv("APP_VERSION", "1.0.0")


class MemoryStore:
    def __init__(self):
        self._tasks, self._next = {}, 1

    def ping(self):
        return True

    def all(self):
        return [self._tasks[k] for k in sorted(self._tasks)]

    def add(self, title):
        task = {"id": self._next, "title": title, "done": False}
        self._tasks[self._next] = task
        self._next += 1
        return task


class RedisStore:
    def __init__(self, host, port):
        import redis  # imported lazily so unit tests don't need it

        self._r = redis.Redis(host=host, port=port, decode_responses=True, socket_timeout=2)

    def ping(self):
        try:
            return bool(self._r.ping())
        except Exception:
            return False

    def all(self):
        raw = self._r.hgetall("tasks")
        return [json.loads(raw[k]) for k in sorted(raw, key=int)]

    def add(self, title):
        task_id = self._r.incr("task_id")
        task = {"id": task_id, "title": title, "done": False}
        self._r.hset("tasks", task_id, json.dumps(task))
        return task


def create_app(store=None):
    app = Flask(__name__)
    if store is None:
        host = os.getenv("REDIS_HOST")
        store = RedisStore(host, int(os.getenv("REDIS_PORT", "6379"))) if host else MemoryStore()

    @app.get("/")
    def index():
        return jsonify(service="taskboard", version=VERSION,
                       environment=os.getenv("APP_ENV", "dev"), pod=socket.gethostname())

    @app.get("/healthz")
    def liveness():
        return jsonify(status="alive")

    @app.get("/readyz")
    def readiness():
        if store.ping():
            return jsonify(status="ready")
        return jsonify(status="storage unavailable"), 503

    @app.get("/api/tasks")
    def list_tasks():
        return jsonify(store.all())

    @app.post("/api/tasks")
    def create_task():
        title = str((request.get_json(silent=True) or {}).get("title", "")).strip()
        if not title:
            return jsonify(error="title is required"), 400
        return jsonify(store.add(title)), 201

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=5000)
