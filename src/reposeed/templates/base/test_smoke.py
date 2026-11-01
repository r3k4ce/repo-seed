from __PACKAGE_NAME__ import project_name


def test_project_name() -> None:
    assert project_name() == "__PROJECT_NAME__"
