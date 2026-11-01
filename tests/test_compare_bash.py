"""Temporary: the Python scaffolder must reproduce new-project.sh byte for byte.

Deleted together with new-project.sh.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from tests.fakes import fake_bin, fake_env

ROOT = Path(__file__).resolve().parent.parent

pytestmark = pytest.mark.skipif(
    sys.platform != "linux" or shutil.which("bash") is None,
    reason="compares against new-project.sh, which needs bash on Linux",
)


def tree(dir: Path) -> dict[str, bytes]:
    """Map every file below ``dir`` (outside ``.git/``) to its bytes, keyed by POSIX path."""
    return {
        path.relative_to(dir).as_posix(): path.read_bytes()
        for path in sorted(dir.rglob("*"))
        if path.is_file() and ".git" not in path.relative_to(dir).parts
    }


def _scaffold(
    command: list[str], project: Path, bin_dir: Path, log: Path
) -> tuple[dict[str, bytes], list[str], str, str]:
    project.mkdir()
    log.write_text("", encoding="utf-8")
    completed = subprocess.run(
        command,
        cwd=project,
        env=fake_env(bin_dir, project),
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    calls = log.read_text(encoding="utf-8").splitlines()
    return tree(project), calls, completed.stdout, completed.stderr


@pytest.mark.parametrize(
    "options",
    [
        [],
        ["--no-git", "--no-install-hooks", "--no-github-actions"],
        ["--no-git"],
        ["--python", "3.13", "--type-mode", "strict"],
        ["--profile", "web"],
        ["--profile", "web", "--no-git", "--no-install-hooks", "--no-github-actions"],
        ["--profile", "web", "--no-git"],
        ["--profile", "web", "--python", "3.13", "--type-mode", "strict"],
    ],
    ids=[
        "base-defaults",
        "base-no-git-hooks-actions",
        "base-no-git-warns",
        "base-python-type-mode",
        "web-defaults",
        "web-no-git-hooks-actions",
        "web-no-git-warns",
        "web-python-type-mode",
    ],
)
def test_matches_bash(tmp_path: Path, options: list[str]) -> None:
    log = tmp_path / "calls.log"
    bin_dir = fake_bin(tmp_path / "bin", log)
    args = ["--name", "demo-app", *options]

    bash = _scaffold(["bash", str(ROOT / "new-project.sh"), *args], tmp_path / "bash", bin_dir, log)
    python = _scaffold([sys.executable, "-m", "reposeed", *args], tmp_path / "python", bin_dir, log)

    bash_tree, bash_calls, bash_out, bash_err = bash
    python_tree, python_calls, python_out, python_err = python
    assert bash_tree
    assert sorted(python_tree) == sorted(bash_tree)
    for path, content in bash_tree.items():
        assert python_tree[path] == content, path
    assert python_calls == bash_calls
    assert python_out == bash_out
    assert python_err == bash_err
    assert bash_calls[0] == "uv --version | ."
