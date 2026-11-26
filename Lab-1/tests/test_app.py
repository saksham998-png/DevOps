import pytest

from app.app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_index(client):
    res = client.get("/")
    assert res.status_code == 200
    assert res.get_json()["service"] == "taskboard"


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "UP"


def test_create_and_list(client):
    res = client.post("/api/tasks", json={"title": "Install Jenkins"})
    assert res.status_code == 201
    assert res.get_json() == {"id": 1, "title": "Install Jenkins", "done": False}
    assert len(client.get("/api/tasks").get_json()) == 1


def test_create_requires_title(client):
    assert client.post("/api/tasks", json={"title": "  "}).status_code == 400
    assert client.post("/api/tasks", data="not json").status_code == 400


def test_mark_done(client):
    client.post("/api/tasks", json={"title": "Write Jenkinsfile"})
    res = client.patch("/api/tasks/1", json={"done": True})
    assert res.status_code == 200
    assert res.get_json()["done"] is True


def test_delete_and_missing(client):
    client.post("/api/tasks", json={"title": "Temp"})
    assert client.delete("/api/tasks/1").status_code == 204
    assert client.delete("/api/tasks/1").status_code == 404
    assert client.patch("/api/tasks/99", json={"done": True}).status_code == 404
