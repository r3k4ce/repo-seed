from demo_app_backend.main import health


def test_health() -> None:
    assert health() == {"status": "ok", "project": "demo-app"}
