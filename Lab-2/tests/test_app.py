import pytest

from app.app import MemoryStore, create_app


class DownStore(MemoryStore):
    def ping(self):
        return False


@pytest.fixture
def client():
    return create_app(MemoryStore()).test_client()


def test_index_reports_pod(client):
    body = client.get("/").get_json()
    assert body["service"] == "taskboard"
    assert body["pod"]


def test_probes(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_not_ready_when_storage_down():
    client = create_app(DownStore()).test_client()
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 503


def test_tasks_roundtrip(client):
    assert client.post("/api/tasks", json={"title": "Build image"}).status_code == 201
    assert client.post("/api/tasks", json={}).status_code == 400
    assert [t["title"] for t in client.get("/api/tasks").get_json()] == ["Build image"]
