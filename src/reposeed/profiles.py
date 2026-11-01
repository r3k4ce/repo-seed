"""What each scaffold profile generates, as data."""

from dataclasses import dataclass
from typing import Literal

PIN_PACKAGES: dict[str, str] = {
    "PY_FASTAPI": "fastapi",
    "PY_UVICORN": "uvicorn",
    "PY_PYTHON_DOTENV": "python-dotenv",
    "PY_PYSIDE6": "PySide6",
    "PY_RUFF": "ruff",
    "PY_PYTEST": "pytest",
    "PY_PYTEST_COV": "pytest-cov",
    "PY_PYRIGHT": "pyright",
    "PY_PRE_COMMIT": "pre-commit",
}
"""Python package name for each ``versions.env`` key that ``uv add`` installs."""


@dataclass(frozen=True)
class FileSpec:
    """One generated file: ``template`` rendered to ``dest`` (which may hold placeholders)."""

    template: str
    dest: str
    mode: Literal["write", "append"] = "write"
    when: Literal["always", "github_actions"] = "always"


@dataclass(frozen=True)
class UvAdd:
    """One ``uv add`` call; ``pins`` are ``versions.env`` keys, ``message`` is printed first."""

    dev: bool
    pins: tuple[str, ...]
    message: str = ""


@dataclass(frozen=True)
class Profile:
    name: str
    layout: Literal["single", "split"]
    uv_adds: tuple[UvAdd, ...]
    files: tuple[FileSpec, ...]
    npm_install: bool
    playwright: bool
    hooks: Literal["per_tool", "pre_push"]
    fresh_paths: tuple[str, ...]
    needs_node: bool


DEV_PINS = ("PY_RUFF", "PY_PYTEST", "PY_PYTEST_COV", "PY_PYRIGHT", "PY_PRE_COMMIT")
RUNTIME_PINS = ("PY_PYTHON_DOTENV",)

BASE_FILES = (
    FileSpec("base/init.py", "src/__PACKAGE_NAME__/__init__.py"),
    FileSpec("base/test_smoke.py", "tests/test_smoke.py"),
    FileSpec("base/pyproject.append.toml", "pyproject.toml", mode="append"),
    FileSpec("common/editorconfig", ".editorconfig"),
    FileSpec("common/gitattributes", ".gitattributes"),
    FileSpec("base/gitignore.append", ".gitignore", mode="append"),
    FileSpec("common/env.example", ".env.example"),
    FileSpec("base/pre-commit-config.yaml", ".pre-commit-config.yaml"),
    FileSpec("scripts/base/check.py", "scripts/check.py"),
    FileSpec("scripts/base/fix.py", "scripts/fix.py"),
    FileSpec("base/README.md", "README.md"),
    FileSpec("base/ci.yml", ".github/workflows/ci.yml", when="github_actions"),
)

BASE = Profile(
    name="base",
    layout="single",
    uv_adds=(
        UvAdd(dev=True, pins=DEV_PINS, message="Adding dev tooling..."),
        UvAdd(dev=False, pins=RUNTIME_PINS, message="Adding runtime dependencies..."),
    ),
    files=BASE_FILES,
    npm_install=False,
    playwright=False,
    hooks="per_tool",
    fresh_paths=("pyproject.toml",),
    needs_node=False,
)

PROFILES: dict[str, Profile] = {profile.name: profile for profile in (BASE,)}
