def test_index_identifies_release(client):
    res = client.get("/")
    assert res.status_code == 200
    body = res.get_json()
    assert {"version", "track", "pod"} <= body.keys()
    assert res.headers["X-App-Version"] == body["version"]
    assert res.headers["X-App-Track"] == body["track"]


def test_probes(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_tasks(client):
    assert client.post("/api/tasks", json={"title": "blue-green"}).status_code == 201
    assert client.post("/api/tasks", json={"title": " "}).status_code == 400
    assert client.get("/api/tasks").get_json() == [{"id": 1, "title": "blue-green"}]


def test_metrics(client):
    client.get("/")
    body = client.get("/metrics").data.decode()
    assert 'http_requests_total{method="GET",route="/",status="200",track="stable",version="dev"} 1.0' in body
    assert "app_info" in body
