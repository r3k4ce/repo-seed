"""Every profile's generated tree and commands must equal ``tests/snapshots/<profile>/``.

After a deliberate change, rewrite the snapshots with
``uv run pytest --update-snapshots tests/test_snapshots.py`` and review the diff.
"""

import shutil
from pathlib import Path

import pytest

from reposeed.cli import PROFILES, parse_args
from reposeed.create import create
from tests.fakes import FakeRunner, tree

SNAPSHOTS = Path(__file__).resolve().parent / "snapshots"
COMMANDS = "commands.txt"
"""Snapshot file listing the FakeRunner calls, one per line."""

# Git honours .gitattributes and .gitignore in every folder, so a generated copy
# inside tests/snapshots/ would change how the snapshot itself is checked out: its
# `* text=auto` beats the root `-text` rule, and Windows checkouts would get CRLF.
# These files are stored under another name.
GIT_FILES = (".gitattributes", ".gitignore")
STORED_SUFFIX = ".snapshot"

UPDATE_HINT = "if the change is deliberate, run: pytest --update-snapshots tests/test_snapshots.py"


def _stored_path(path: str) -> str:
    return f"{path}{STORED_SUFFIX}" if path.rsplit("/", 1)[-1] in GIT_FILES else path


def _generate(profile: str, tmp_path: Path) -> dict[str, bytes]:
    project = tmp_path / "demo-app"
    project.mkdir()
    runner = FakeRunner(project)
    create(parse_args(["--name", "demo-app", "--profile", profile]), runner, project, tmp_path)
    generated = tree(project)
    files = {_stored_path(path): content for path, content in generated.items()}
    assert len(files) == len(generated)
    assert COMMANDS not in files
    files[COMMANDS] = "".join(f"{call}\n" for call in runner.calls).encode("utf-8")
    return files


def _rewrite(folder: Path, files: dict[str, bytes]) -> None:
    if folder.exists():
        shutil.rmtree(folder)
    for path, content in files.items():
        target = folder / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)


@pytest.mark.parametrize("profile", PROFILES)
def test_snapshot(profile: str, tmp_path: Path, request: pytest.FixtureRequest) -> None:
    actual = _generate(profile, tmp_path)
    folder = SNAPSHOTS / profile
    if request.config.getoption("--update-snapshots"):
        _rewrite(folder, actual)

    expected = tree(folder) if folder.is_dir() else {}
    assert sorted(actual) == sorted(expected), UPDATE_HINT
    for path, content in expected.items():
        assert actual[path] == content, f"{profile}/{path} differs; {UPDATE_HINT}"
