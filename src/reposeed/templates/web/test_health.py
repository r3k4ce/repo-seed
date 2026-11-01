from __PACKAGE_NAME___backend.main import health


def test_health() -> None:
    assert health() == {"status": "ok", "project": "__PROJECT_NAME__"}
