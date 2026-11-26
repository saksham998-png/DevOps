"""Taskboard - a small task-tracking web service used for Lab 1 (CI with Git & Jenkins)."""
import os
import time
from itertools import count

from flask import Flask, jsonify, request

START = time.time()
VERSION = os.getenv("APP_VERSION", "dev")


def create_app():
    app = Flask(__name__)
    tasks = {}
    ids = count(1)

    @app.get("/")
    def index():
        return jsonify(service="taskboard", lab="Lab 1", version=VERSION)

    @app.get("/health")
    def health():
        return jsonify(status="UP", version=VERSION, uptime_s=round(time.time() - START, 1))

    @app.get("/api/tasks")
    def list_tasks():
        return jsonify(list(tasks.values()))

    @app.post("/api/tasks")
    def create_task():
        body = request.get_json(silent=True) or {}
        title = str(body.get("title", "")).strip()
        if not title:
            return jsonify(error="title is required"), 400
        task = {"id": next(ids), "title": title, "done": False}
        tasks[task["id"]] = task
        return jsonify(task), 201

    @app.patch("/api/tasks/<int:task_id>")
    def update_task(task_id):
        task = tasks.get(task_id)
        if task is None:
            return jsonify(error="not found"), 404
        body = request.get_json(silent=True) or {}
        if "done" in body:
            task["done"] = bool(body["done"])
        return jsonify(task)

    @app.delete("/api/tasks/<int:task_id>")
    def delete_task(task_id):
        if tasks.pop(task_id, None) is None:
            return jsonify(error="not found"), 404
        return "", 204

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
