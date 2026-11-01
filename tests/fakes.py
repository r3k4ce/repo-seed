"""Fake external tools for create() tests.

``FakeRunner`` stands in for ``SubprocessRunner`` inside the test process.
``fake_bin`` writes Bash scripts for ``uv``, ``node``, ``npm`` and ``git`` so a real
scaffolder process (new-project.ps1 or ``python -m reposeed``) can run against
them, and ``scaffold`` runs one. Both record each command as
``"<command> | <cwd relative to the project>"``. ``fake_bin`` and ``scaffold`` serve
only tests/test_compare_powershell.py and go away with new-project.ps1.
"""

import os
import stat
import subprocess
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path

from reposeed.tools import Runner
from reposeed.versions import bundled_versions

FAKE_ROOT_ENV = "FAKE_PROJECT_ROOT"
"""Environment variable naming the project folder that ``fake_bin`` logs relative to."""

# What `uv init` writes for a git repository (uv 0.13.3).
UV_GITIGNORE = """\
# Python-generated files
__pycache__/
*.py[oc]
build/
dist/
wheels/
*.egg-info

# Virtual environments
.venv
"""

# What `uv init --package` writes (uv 0.13.3), without the `authors` line uv
# takes from the git configuration.
UV_PYPROJECT = """\
[project]
name = "{name}"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
requires-python = ">={python}"
dependencies = []

[project.scripts]
{name} = "{package}:main"

[build-system]
requires = ["uv_build>=0.13.3,<0.14.0"]
build-backend = "uv_build"
"""

UV_INIT_PY = """\
def main() -> None:
    print("Hello from {name}!")
"""


def _relative(path: Path, root: Path) -> str:
    relative = path.resolve().relative_to(root.resolve()).as_posix()
    return relative or "."


class FakeRunner(Runner):
    """Records commands instead of running them and simulates `uv init` and `git init`."""

    def __init__(
        self,
        root: Path,
        *,
        missing: Iterable[str] = (),
        outputs: Mapping[str, str] | None = None,
    ) -> None:
        self.root = root
        self.calls: list[str] = []
        self.missing = set(missing)
        # The oldest uv and Node.js that versions.env allows.
        versions = bundled_versions()
        self.outputs = {
            "uv": f"uv {versions['UV_MIN']} (fake)",
            "node": f"v{versions['NODE_MIN']}",
            **(outputs or {}),
        }

    def run(self, command: Sequence[str], cwd: Path) -> None:
        self.calls.append(f"{' '.join(command)} | {_relative(cwd, self.root)}")
        if list(command[:2]) == ["uv", "init"]:
            self._uv_init(command[2:], cwd)
        elif list(command[:2]) == ["git", "init"]:
            (cwd / ".git").mkdir(exist_ok=True)

    def which(self, name: str) -> str | None:
        return None if name in self.missing else f"/fake/bin/{name}"

    def output(self, command: Sequence[str]) -> str:
        self.calls.append(f"{' '.join(command)} | .")
        return self.outputs.get(command[0], "")

    def _uv_init(self, args: Sequence[str], cwd: Path) -> None:
        options: dict[str, str] = {}
        target = cwd
        rest = list(args)
        while rest:
            arg = rest.pop(0)
            if arg in ("--name", "--python", "--vcs"):
                options[arg] = rest.pop(0)
            elif not arg.startswith("--"):
                target = cwd / arg
        name = options["--name"]
        package = name.replace("-", "_")
        python = options["--python"]
        target.mkdir(parents=True, exist_ok=True)
        (target / "pyproject.toml").write_text(
            UV_PYPROJECT.format(name=name, package=package, python=python), newline="\n"
        )
        (target / ".python-version").write_text(f"{python}\n", newline="\n")
        (target / "README.md").write_text("", newline="\n")
        source = target / "src" / package
        source.mkdir(parents=True, exist_ok=True)
        (source / "__init__.py").write_text(UV_INIT_PY.format(name=name), newline="\n")
        if options.get("--vcs") != "none":
            (target / ".git").mkdir(exist_ok=True)
            (target / ".gitignore").write_text(UV_GITIGNORE, newline="\n")


_LOG_CALL = r"""
log_call() {
  local here root relative line
  here="$(pwd -P)"
  root="$(cd "${FAKE_PROJECT_ROOT:-$here}" && pwd -P)"
  relative="."
  if [[ "$here" != "$root" ]]; then
    relative="${here#"$root"/}"
  fi
  line="$TOOL"
  if [[ $# -gt 0 ]]; then
    line+=" $*"
  fi
  printf '%s | %s\n' "$line" "$relative" >>"$LOG"
}
log_call "$@"
"""

# A minimal `uv init` (pyproject.toml and package `__init__.py`), plus the `.git/`
# folder and `.gitignore` that a real `uv init` creates without `--vcs none`.
_UV_BODY = r"""
if [[ "${1-}" == "--version" ]]; then
  printf 'uv 99.0.0 (fake)\n'
  exit 0
fi

if [[ "${1-}" == "init" ]]; then
  project_dir="."
  package_name="python_project"
  vcs="git"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        package_name="${2//-/_}"
        shift 2
        ;;
      --vcs)
        vcs="$2"
        shift 2
        ;;
      --python)
        shift 2
        ;;
      --package | --no-workspace)
        shift
        ;;
      init)
        shift
        ;;
      *)
        project_dir="$1"
        shift
        ;;
    esac
  done

  mkdir -p "$project_dir/src/$package_name"
  printf '[project]\nname = "%s"\nversion = "0.1.0"\n' "$package_name" \
    >"$project_dir/pyproject.toml"
  printf 'def project_name() -> str:\n    return "%s"\n' "$package_name" \
    >"$project_dir/src/$package_name/__init__.py"
  if [[ "$vcs" != "none" ]]; then
    mkdir -p "$project_dir/.git"
    cat >"$project_dir/.gitignore" <<'GITIGNORE'
__UV_GITIGNORE__GITIGNORE
  fi
fi
"""

_NODE_BODY = r"""
if [[ "${1-}" == "--version" ]]; then
  printf 'v99.0.0\n'
fi
"""

_GIT_BODY = r"""
if [[ "${1-}" == "init" ]]; then
  mkdir -p .git
fi
"""


def fake_bin(dir: Path, log: Path) -> Path:
    """Write fake ``uv``, ``node``, ``npm`` and ``git`` into ``dir``, logging to ``log``.

    Each call appends ``<tool> <args> | <cwd>`` to ``log``, with ``cwd`` relative
    to ``$FAKE_PROJECT_ROOT`` (``.`` for the root).
    """
    bodies = {
        "uv": _UV_BODY.replace("__UV_GITIGNORE__", UV_GITIGNORE),
        "node": _NODE_BODY,
        "npm": "",
        "git": _GIT_BODY,
    }
    dir.mkdir(parents=True, exist_ok=True)
    for tool, body in bodies.items():
        script = dir / tool
        header = f"#!/usr/bin/env bash\nset -euo pipefail\nTOOL={tool}\nLOG='{log}'\n"
        script.write_text(header + _LOG_CALL + body + "exit 0\n", newline="\n")
        script.chmod(script.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return dir


def fake_env(bin_dir: Path, root: Path) -> dict[str, str]:
    """Return an environment with ``bin_dir`` first on PATH, logging relative to ``root``."""
    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    env[FAKE_ROOT_ENV] = str(root)
    return env


def tree(dir: Path) -> dict[str, bytes]:
    """Map every file below ``dir`` (outside ``.git/``) to its bytes, keyed by POSIX path."""
    return {
        path.relative_to(dir).as_posix(): path.read_bytes()
        for path in sorted(dir.rglob("*"))
        if path.is_file() and ".git" not in path.relative_to(dir).parts
    }


def scaffold(
    command: list[str], project: Path, bin_dir: Path, log: Path
) -> tuple[dict[str, bytes], list[str], str, str]:
    """Run a scaffolder in a new ``project`` folder against the fakes in ``bin_dir``.

    Returns the generated tree, the logged calls, stdout and stderr.
    """
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
