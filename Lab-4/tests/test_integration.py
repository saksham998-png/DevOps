"""Behaviour that deployment strategies rely on: readiness, draining, failure injection."""
from app.app import MemoryStore, create_app


class DownStore(MemoryStore):
    def ping(self):
        return False


def test_not_ready_when_storage_down(secrets_dir):
    client = create_app(DownStore(), fail_rate=0).test_client()
    assert client.get("/healthz").status_code == 200   # still alive: don't restart it
    assert client.get("/readyz").status_code == 503    # but take it out of the Service


def test_drain_removes_pod_from_rotation(client):
    assert client.post("/admin/drain", headers={"Authorization": "Bearer test-api-key-456"}).status_code == 200
    assert client.get("/readyz").status_code == 503
    assert client.get("/healthz").status_code == 200


def test_fail_rate_one_breaks_api_only(secrets_dir):
    client = create_app(MemoryStore(), fail_rate=1.0).test_client()
    assert client.get("/api/tasks").status_code == 500
    assert client.post("/api/tasks", json={"title": "x"}).status_code == 500
    assert client.get("/healthz").status_code == 200
    body = client.get("/metrics").data.decode()
    assert 'status="500"' in body


def test_fail_rate_zero_never_fails(client):
    assert all(client.get("/api/tasks").status_code == 200 for _ in range(50))


class FakeRedis:
    def __init__(self, **kwargs):
        self.kwargs, self.hash, self.counter, self.up = kwargs, {}, 0, True

    def ping(self):
        if not self.up:
            raise ConnectionError("down")
        return True

    def incr(self, key):
        self.counter += 1
        return self.counter

    def hset(self, name, key, value):
        self.hash[str(key)] = value

    def hgetall(self, name):
        return dict(self.hash)


def test_redis_store_uses_secret_and_persists(secrets_dir, monkeypatch):
    import redis

    from app.app import RedisStore

    monkeypatch.setattr(redis, "Redis", FakeRedis)
    store = RedisStore("redis", 6379, "test-db-pass-123")
    assert store.r.kwargs["password"] == "test-db-pass-123"
    client = create_app(store, fail_rate=0).test_client()
    for title in ("one", "two"):
        client.post("/api/tasks", json={"title": title})
    assert [t["title"] for t in client.get("/api/tasks").get_json()] == ["one", "two"]
    store.r.up = False
    assert client.get("/readyz").status_code == 503
