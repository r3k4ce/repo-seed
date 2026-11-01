"""Temporary: the Python desktop profile must reproduce new-project.ps1 byte for byte,
except for the paths in ``DELIBERATE_DESKTOP_CHANGES``.

Runs only where ``pwsh`` is installed on Linux (the fakes are Bash scripts), for
example on ubuntu-latest CI runners. Deleted together with new-project.ps1.
"""

import shutil
import sys
from pathlib import Path

import pytest

from tests.fakes import fake_bin, scaffold

ROOT = Path(__file__).resolve().parent.parent

DELIBERATE_DESKTOP_CHANGES = frozenset({".github/workflows/ci.yml"})
"""Paths where the desktop profile intentionally departs from new-project.ps1.

The spec's deliberate change "install libegl1 in generated desktop CI" adds a step
to ``.github/workflows/ci.yml``. Nothing else may differ."""

pytestmark = pytest.mark.skipif(
    sys.platform != "linux" or shutil.which("pwsh") is None,
    reason="compares against new-project.ps1, which needs pwsh on Linux",
)


@pytest.mark.parametrize(
    ("python_options", "powershell_options"),
    [
        (
            ["--no-git", "--no-install-hooks", "--no-github-actions"],
            ["-NoGit", "-NoInstallHooks", "-NoGitHubActions"],
        ),
        ([], []),
        (["--python", "3.13", "--type-mode", "strict"], ["-Python", "3.13", "-TypeMode", "strict"]),
    ],
    ids=["desktop-no-git-hooks-actions", "desktop-defaults", "desktop-python-type-mode"],
)
def test_matches_powershell(
    tmp_path: Path, python_options: list[str], powershell_options: list[str]
) -> None:
    log = tmp_path / "calls.log"
    bin_dir = fake_bin(tmp_path / "bin", log)

    powershell = scaffold(
        [
            "pwsh",
            "-NoProfile",
            "-NonInteractive",
            "-File",
            str(ROOT / "new-project.ps1"),
            "-Name",
            "demo-app",
            "-Profile",
            "desktop",
            *powershell_options,
        ],
        tmp_path / "powershell",
        bin_dir,
        log,
    )
    python = scaffold(
        [
            sys.executable,
            "-m",
            "reposeed",
            "--name",
            "demo-app",
            "--profile",
            "desktop",
            *python_options,
        ],
        tmp_path / "python",
        bin_dir,
        log,
    )

    # stdout/stderr are not compared: PowerShell's Write-Host and Write-Warning
    # formatting is not something the Python scaffolder reproduces.
    powershell_tree, powershell_calls, _, _ = powershell
    python_tree, python_calls, _, _ = python
    assert powershell_tree
    assert sorted(python_tree) == sorted(powershell_tree)
    for path, content in powershell_tree.items():
        if path not in DELIBERATE_DESKTOP_CHANGES:
            assert python_tree[path] == content, path
    assert python_calls == powershell_calls
    assert powershell_calls[0] == "uv --version | ."
