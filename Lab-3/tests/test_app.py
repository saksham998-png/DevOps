import json

import pytest

from app.app import create_app


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("FLAGS_FILE", raising=False)
    monkeypatch.delenv("FEATURE_PRIORITY_TASKS", raising=False)
    return create_app().test_client()


def test_health(client):
    assert client.get("/health").get_json()["status"] == "UP"


def test_flag_off_by_default(client):
    assert client.get("/api/flags").get_json() == {"priority_tasks": False}
    task = client.post("/api/tasks", json={"title": "a", "priority": 5}).get_json()
    assert "priority" not in task
    assert b"OFF" in client.get("/").data


def test_flag_from_env_sorts_by_priority(client, monkeypatch):
    monkeypatch.setenv("FEATURE_PRIORITY_TASKS", "true")
    client.post("/api/tasks", json={"title": "low", "priority": 1})
    client.post("/api/tasks", json={"title": "high", "priority": 5})
    assert [t["title"] for t in client.get("/api/tasks").get_json()] == ["high", "low"]
    assert client.post("/api/tasks", json={"title": "x", "priority": "abc"}).status_code == 400


def test_flag_file_toggles_at_runtime(client, monkeypatch, tmp_path):
    flags = tmp_path / "flags.json"
    flags.write_text(json.dumps({"priority_tasks": True}))
    monkeypatch.setenv("FLAGS_FILE", str(flags))
    assert client.get("/api/flags").get_json()["priority_tasks"] is True
    flags.write_text(json.dumps({"priority_tasks": False}))
    assert client.get("/api/flags").get_json()["priority_tasks"] is False


def test_metrics_exposed(client, monkeypatch):
    monkeypatch.setenv("FEATURE_PRIORITY_TASKS", "1")
    client.post("/api/tasks", json={"title": "metric me"})
    body = client.get("/metrics").data.decode()
    assert 'taskboard_http_requests_total{method="POST",route="/api/tasks",status="201"} 1.0' in body
    assert 'taskboard_feature_flag_enabled{flag="priority_tasks"} 1.0' in body
    assert "taskboard_tasks 1.0" in body


def test_logs_are_json(client, capsys):
    client.get("/health", headers={"X-Request-ID": "abc123"})
    line = [l for l in capsys.readouterr().out.splitlines() if "http_request" in l][-1]
    entry = json.loads(line)
    assert entry["service"] == "taskboard"
    assert entry["request_id"] == "abc123"
    assert entry["status"] == 200


def test_home_escapes_titles(client):
    client.post("/api/tasks", json={"title": "<script>alert(1)</script>"})
    page = client.get("/").data
    assert b"<script>" not in page
    assert b"&lt;script&gt;" in page
