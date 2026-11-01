from __BACKEND_PACKAGE_NAME__.main import health


def test_health() -> None:
    assert health() == {"status": "ok", "project": "__PROJECT_NAME__"}
