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
    """One scaffold profile.

    ``layout`` is ``single`` (a uv project at the root) or ``split`` (``backend/``
    and ``frontend/``). ``header`` is the first line printed and may hold placeholders.
    """

    name: str
    layout: Literal["single", "split"]
    header: str
    uv_adds: tuple[UvAdd, ...]
    files: tuple[FileSpec, ...]
    npm_install: bool
    playwright: bool
    hooks: Literal["per_tool", "pre_push"]
    fresh_paths: tuple[str, ...]
    needs_node: bool


DEV_PINS = ("PY_RUFF", "PY_PYTEST", "PY_PYTEST_COV", "PY_PYRIGHT", "PY_PRE_COMMIT")
RUNTIME_PINS = ("PY_PYTHON_DOTENV",)

SINGLE_HEADER = (
    "Creating Python project: __PROJECT_NAME__ (__PACKAGE_NAME__, Python __PYTHON_VERSION__, "
    "pyright __TYPE_MODE__, profile __PROFILE__)"
)

BASE_FILES = (
    FileSpec("common/init.py", "src/__PACKAGE_NAME__/__init__.py"),
    FileSpec("base/test_smoke.py", "tests/test_smoke.py"),
    FileSpec("base/pyproject.append.toml", "pyproject.toml", mode="append"),
    FileSpec("base/editorconfig", ".editorconfig"),
    FileSpec("base/gitattributes", ".gitattributes"),
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
    header=SINGLE_HEADER,
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

SPLIT_FRESH_PATHS = ("backend", "frontend", "package.json", "pyproject.toml")

WEB = Profile(
    name="web",
    layout="split",
    header=(
        "Creating __PROFILE__ project: __PROJECT_NAME__ "
        "(FastAPI backend, React TypeScript frontend)"
    ),
    uv_adds=(
        UvAdd(dev=False, pins=(*RUNTIME_PINS, "PY_FASTAPI", "PY_UVICORN")),
        UvAdd(dev=True, pins=DEV_PINS),
    ),
    files=(
        FileSpec("common/init.py", "backend/src/__BACKEND_PACKAGE_NAME__/__init__.py"),
        FileSpec("web/backend_main.py", "backend/src/__BACKEND_PACKAGE_NAME__/main.py"),
        FileSpec("web/test_health.py", "backend/tests/test_health.py"),
        FileSpec("web/pyproject.append.toml", "backend/pyproject.toml", mode="append"),
        FileSpec("web/package.json", "frontend/package.json"),
        FileSpec("common/npmrc", "frontend/.npmrc"),
        FileSpec("web/index.html", "frontend/index.html"),
        FileSpec("common/tsconfig.json", "frontend/tsconfig.json"),
        FileSpec("web/tsconfig.app.json", "frontend/tsconfig.app.json"),
        FileSpec("common/tsconfig.node.json", "frontend/tsconfig.node.json"),
        FileSpec("web/vite.config.ts", "frontend/vite.config.ts"),
        FileSpec("web/eslint.config.js", "frontend/eslint.config.js"),
        FileSpec("web/frontend_main.tsx", "frontend/src/main.tsx"),
        FileSpec("web/App.tsx", "frontend/src/App.tsx"),
        FileSpec("web/App.test.tsx", "frontend/src/App.test.tsx"),
        FileSpec("web/test_setup.ts", "frontend/src/test/setup.ts"),
        FileSpec("common/vite-env.d.ts", "frontend/src/vite-env.d.ts"),
        FileSpec("web/style.css", "frontend/src/style.css"),
        FileSpec("web/editorconfig", ".editorconfig"),
        FileSpec("web/gitattributes", ".gitattributes"),
        FileSpec("web/gitignore.append", ".gitignore", mode="append"),
        FileSpec("common/env.example", ".env.example"),
        FileSpec("scripts/web/check.py", "scripts/check.py"),
        FileSpec("scripts/web/fix.py", "scripts/fix.py"),
        FileSpec("web/README.md", "README.md"),
        FileSpec("web/pre-commit-config.yaml", ".pre-commit-config.yaml"),
        FileSpec("web/ci.yml", ".github/workflows/ci.yml", when="github_actions"),
    ),
    npm_install=True,
    playwright=False,
    hooks="pre_push",
    fresh_paths=SPLIT_FRESH_PATHS,
    needs_node=True,
)

GAME = Profile(
    name="game",
    layout="split",
    header=(
        "Creating __PROFILE__ project: __PROJECT_NAME__ (FastAPI backend, Phaser game frontend)"
    ),
    uv_adds=WEB.uv_adds,
    files=(
        FileSpec("common/init.py", "backend/src/__BACKEND_PACKAGE_NAME__/__init__.py"),
        FileSpec("game/backend_main.py", "backend/src/__BACKEND_PACKAGE_NAME__/main.py"),
        FileSpec("game/test_game_api.py", "backend/tests/test_game_api.py"),
        FileSpec("web/pyproject.append.toml", "backend/pyproject.toml", mode="append"),
        FileSpec("game/package.json", "frontend/package.json"),
        FileSpec("common/npmrc", "frontend/.npmrc"),
        FileSpec("game/index.html", "frontend/index.html"),
        FileSpec("common/tsconfig.json", "frontend/tsconfig.json"),
        FileSpec("game/tsconfig.app.json", "frontend/tsconfig.app.json"),
        FileSpec("common/tsconfig.node.json", "frontend/tsconfig.node.json"),
        FileSpec("game/vite.config.ts", "frontend/vite.config.ts"),
        FileSpec("game/eslint.config.js", "frontend/eslint.config.js"),
        FileSpec("game/frontend_main.ts", "frontend/src/main.ts"),
        FileSpec("game/scene.ts", "frontend/src/game/GameScene.ts"),
        FileSpec("game/playwright.config.ts", "frontend/playwright.config.ts"),
        FileSpec("game/game-smoke.spec.ts", "frontend/tests/game-smoke.spec.ts"),
        FileSpec("common/vite-env.d.ts", "frontend/src/vite-env.d.ts"),
        FileSpec("game/style.css", "frontend/src/style.css"),
        FileSpec("web/editorconfig", ".editorconfig"),
        FileSpec("web/gitattributes", ".gitattributes"),
        FileSpec("web/gitignore.append", ".gitignore", mode="append"),
        FileSpec("common/env.example", ".env.example"),
        FileSpec("scripts/game/check.py", "scripts/check.py"),
        FileSpec("scripts/game/fix.py", "scripts/fix.py"),
        FileSpec("game/README.md", "README.md"),
        FileSpec("web/pre-commit-config.yaml", ".pre-commit-config.yaml"),
        FileSpec("game/ci.yml", ".github/workflows/ci.yml", when="github_actions"),
    ),
    npm_install=True,
    playwright=True,
    hooks="pre_push",
    fresh_paths=SPLIT_FRESH_PATHS,
    needs_node=True,
)

PROFILES: dict[str, Profile] = {profile.name: profile for profile in (BASE, WEB, GAME)}
