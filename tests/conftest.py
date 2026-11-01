import pytest

# Snapshot folders hold generated projects, including their own tests; they are data.
collect_ignore = ["snapshots"]


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--update-snapshots",
        action="store_true",
        default=False,
        help="Rewrite tests/snapshots/ from the current output instead of comparing.",
    )
