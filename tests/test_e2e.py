"""Real scaffolds: every profile is created with the real tools and its checks pass.

Slow and network-bound, so deselected by default; run with ``uv run pytest -m e2e``.
The game profile downloads Playwright Chromium and runs only with ``REPOSEED_E2E_GAME=1``.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from reposeed.cli import PROFILES

pytestmark = pytest.mark.e2e

# Folder below the project root to run check.py from, to show that the scripts
# resolve paths from their own location rather than the caller's.
SUBFOLDER = {"base": "tests", "desktop": "tests", "web": "backend", "game": "backend"}


def _env(profile: str) -> dict[str, str]:
    # The outer `uv run pytest` points VIRTUAL_ENV at RepoSeed's own environment;
    # uv inside the generated project must use the project's.
    env = {key: value for key, value in os.environ.items() if key != "VIRTUAL_ENV"}
    if profile == "desktop":
        env["QT_QPA_PLATFORM"] = "offscreen"
    return env


def _run(command: list[str], cwd: Path, env: dict[str, str]) -> None:
    completed = subprocess.run(command, cwd=cwd, env=env, check=False)
    assert completed.returncode == 0, f"{command} failed in {cwd}"


@pytest.mark.parametrize("profile", PROFILES)
def test_scaffold_checks_pass(profile: str, tmp_path: Path) -> None:
    if profile == "game" and os.environ.get("REPOSEED_E2E_GAME") != "1":
        pytest.skip("set REPOSEED_E2E_GAME=1 to run the game e2e")
    uv = shutil.which("uv")
    assert uv is not None, "uv is not on PATH"
    name = f"{profile}-demo"
    project = tmp_path / name
    project.mkdir()
    env = _env(profile)

    _run(
        [
            sys.executable,
            "-m",
            "reposeed",
            "--profile",
            profile,
            "--name",
            name,
            "--no-git",
            "--no-install-hooks",
            "--no-github-actions",
        ],
        project,
        env,
    )
    for script in ("scripts/check.py", "scripts/fix.py", "scripts/check.py"):
        _run([uv, "run", script], project, env)
    _run([uv, "run", "../scripts/check.py"], project / SUBFOLDER[profile], env)
