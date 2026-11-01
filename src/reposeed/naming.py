"""Project, package and tool-target naming rules."""

import re

_DEFAULT_PROJECT_NAME = "python-project"
_DEFAULT_RUFF_TARGET = "py312"


def project_name(raw: str) -> str:
    """Lowercase ``raw``, collapse runs of other characters to ``-`` and trim dashes."""
    name = re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")
    return name or _DEFAULT_PROJECT_NAME


def package_name(project: str) -> str:
    """Return the importable package name for a project name."""
    return project.replace("-", "_")


def ruff_target(python: str) -> str:
    """Map a Python version such as ``3.13`` to a ruff target such as ``py313``."""
    match = re.search(r"([0-9]+)\.([0-9]+)", python)
    if match is None:
        return _DEFAULT_RUFF_TARGET
    return f"py{match.group(1)}{match.group(2)}"
