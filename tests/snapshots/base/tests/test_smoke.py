from demo_app import project_name


def test_project_name() -> None:
    assert project_name() == "demo-app"
