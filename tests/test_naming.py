import pytest

from reposeed.naming import package_name, project_name, ruff_target


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("My App!", "my-app"),
        ("--x__y--", "x-y"),
        ("!!!", "python-project"),
        ("", "python-project"),
        ("   ", "python-project"),
        ("Already-Fine", "already-fine"),
    ],
)
def test_project_name(raw: str, expected: str) -> None:
    assert project_name(raw) == expected


def test_package_name() -> None:
    assert package_name("my-app") == "my_app"


@pytest.mark.parametrize(
    ("python", "expected"),
    [("3.13", "py313"), ("3.12.4", "py312"), ("latest", "py312"), ("", "py312")],
)
def test_ruff_target(python: str, expected: str) -> None:
    assert ruff_target(python) == expected
