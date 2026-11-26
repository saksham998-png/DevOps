import pytest

from app.app import MemoryStore, create_app


@pytest.fixture
def secrets_dir(tmp_path, monkeypatch):
    (tmp_path / "db_password").write_text("test-db-pass-123\n")
    (tmp_path / "api_key").write_text("test-api-key-456")
    monkeypatch.setenv("SECRETS_DIR", str(tmp_path))
    monkeypatch.delenv("DB_PASSWORD", raising=False)
    monkeypatch.delenv("API_KEY", raising=False)
    return tmp_path


@pytest.fixture
def client(secrets_dir):
    return create_app(MemoryStore(), fail_rate=0).test_client()
