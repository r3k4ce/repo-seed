"""External tool access: command runner, lookup and version checks."""

import re
import shutil
import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import Protocol

_VERSION = re.compile(r"\d+(?:\.\d+)+")


class SetupError(Exception):
    """A user-facing problem with the environment; the message is shown as is."""


class CommandError(Exception):
    """An external command exited with a non-zero status."""

    def __init__(self, command: Sequence[str], code: int) -> None:
        self.command = tuple(command)
        self.code = code
        super().__init__(f"'{' '.join(self.command)}' failed with exit code {code}")


class Runner(Protocol):
    """Everything RepoSeed needs from the outside world."""

    def run(self, command: Sequence[str], cwd: Path) -> None: ...

    def which(self, name: str) -> str | None: ...

    def output(self, command: Sequence[str]) -> str: ...


class SubprocessRunner:
    """Runs real commands without a shell, resolving them like the user's shell would."""

    def run(self, command: Sequence[str], cwd: Path) -> None:
        name = command[0]
        resolved = shutil.which(name)
        if resolved is None:
            raise SetupError(f"'{name}' was not found on PATH.")
        completed = subprocess.run([resolved, *command[1:]], cwd=cwd, check=False)
        if completed.returncode != 0:
            raise CommandError(command, completed.returncode)

    def which(self, name: str) -> str | None:
        return shutil.which(name)

    def output(self, command: Sequence[str]) -> str:
        """Return the command's stdout, or an empty string if it cannot be run."""
        resolved = shutil.which(command[0])
        if resolved is None:
            return ""
        try:
            completed = subprocess.run(
                [resolved, *command[1:]],
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
        except OSError:
            return ""
        return completed.stdout


def _parts(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def version_at_least(actual: str, minimum: str) -> bool:
    """Compare dotted integer versions; missing trailing parts count as zero."""
    left, right = _parts(actual), _parts(minimum)
    size = max(len(left), len(right))
    return left + (0,) * (size - len(left)) >= right + (0,) * (size - len(right))


def extract_version(text: str) -> str | None:
    """Return the first dotted version number found in ``text``."""
    match = _VERSION.search(text)
    return match.group(0) if match else None


def require_uv(runner: Runner, minimum: str) -> None:
    if runner.which("uv") is None:
        raise SetupError("uv was not found on PATH. Install uv first, then rerun this script.")
    actual = extract_version(runner.output(["uv", "--version"]))
    if actual is None:
        raise SetupError("Could not read the uv version from 'uv --version'.")
    if not version_at_least(actual, minimum):
        raise SetupError(
            f"uv {actual} is too old. RepoSeed needs uv {minimum} or newer. "
            "Run 'uv self update' and retry."
        )


def require_node(runner: Runner, minimum: str, profile: str) -> None:
    if runner.which("node") is None or runner.which("npm") is None:
        raise SetupError(
            "node and npm were not found on PATH. Install Node.js first, then rerun this script."
        )
    actual = extract_version(runner.output(["node", "--version"]))
    if actual is None:
        raise SetupError("Could not read the Node.js version from 'node --version'.")
    if not version_at_least(actual, minimum):
        raise SetupError(
            f"Node.js {actual} is too old. RepoSeed needs Node.js {minimum} or newer "
            f"for the {profile} profile."
        )
