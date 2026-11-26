"""Secret handling: never exposed, no built-in defaults, admin endpoint protected."""
import pathlib

from app.app import MemoryStore, create_app

APP_SOURCE = (pathlib.Path(__file__).parents[1] / "app" / "app.py").read_text()


def test_config_shows_fingerprints_not_values(client, capsys):
    res = client.get("/api/config")
    text = res.get_data(as_text=True) + capsys.readouterr().out
    assert "test-db-pass-123" not in text
    assert "test-api-key-456" not in text
    assert res.get_json()["secrets"]["db_password"].startswith("sha256:")


def test_missing_secrets_are_reported_not_defaulted(tmp_path, monkeypatch):
    monkeypatch.setenv("SECRETS_DIR", str(tmp_path))  # empty dir
    monkeypatch.delenv("DB_PASSWORD", raising=False)
    monkeypatch.delenv("API_KEY", raising=False)
    client = create_app(MemoryStore(), fail_rate=0).test_client()
    assert client.get("/api/config").get_json()["secrets"] == {"db_password": "missing", "api_key": "missing"}


def test_no_hardcoded_secret_defaults_in_source():
    for marker in ('getenv("DB_PASSWORD",', 'getenv("API_KEY",', "password=\"", "api_key=\""):
        assert marker not in APP_SOURCE


def test_drain_requires_token(client):
    assert client.post("/admin/drain").status_code == 401
    assert client.post("/admin/drain", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/readyz").status_code == 200


def test_drain_disabled_without_api_key(tmp_path, monkeypatch):
    monkeypatch.setenv("SECRETS_DIR", str(tmp_path))
    monkeypatch.delenv("API_KEY", raising=False)
    client = create_app(MemoryStore(), fail_rate=0).test_client()
    assert client.post("/admin/drain", headers={"Authorization": "Bearer "}).status_code == 401


def test_method_not_allowed_and_headers(client):
    assert client.delete("/api/config").status_code == 405
    assert client.get("/").headers["X-Content-Type-Options"] == "nosniff"
