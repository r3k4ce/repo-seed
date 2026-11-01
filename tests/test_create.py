from dataclasses import replace
from pathlib import Path

import pytest

import reposeed.create
from reposeed.cli import Options
from reposeed.create import create
from reposeed.profiles import PIN_PACKAGES, PROFILES
from reposeed.render import read_template
from reposeed.tools import SetupError
from reposeed.versions import VersionsError, bundled_versions
from tests.fakes import FakeRunner, tree

BASE = Options(
    name="demo-app",
    python="3.12",
    type_mode="standard",
    profile="base",
    no_git=False,
    no_install_hooks=False,
    no_github_actions=False,
)

DEV_ADD = (
    "uv add --dev ruff==0.16.9 pytest==9.1.1 pytest-cov==7.1.0 pyright==1.1.414 "
    "pre-commit==4.6.2 | ."
)
NO_HOOKS = "Warning: No .git directory found. Skipping hook installation.\n"


def _project(tmp_path: Path) -> Path:
    project = tmp_path / "project"
    project.mkdir(parents=True)
    return project


def _create(options: Options, project: Path) -> FakeRunner:
    runner = FakeRunner(project)
    create(options, runner, project, project.parent / "home")
    return runner


def test_base_calls(tmp_path: Path) -> None:
    runner = _create(BASE, _project(tmp_path))
    assert runner.calls == [
        "uv --version | .",
        "uv init --package --name demo-app --python 3.12 | .",
        DEV_ADD,
        "uv add python-dotenv==1.2.3 | .",
        "uv run pre-commit install | .",
        "uv run pre-commit install --hook-type pre-push | .",
    ]


def test_base_stdout(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _create(BASE, _project(tmp_path))
    captured = capsys.readouterr()
    assert captured.out == (
        "Creating Python project: demo-app "
        "(demo_app, Python 3.12, pyright standard, profile base)\n"
        "Adding dev tooling...\n"
        "Adding runtime dependencies...\n"
        "Installing pre-commit and pre-push hooks...\n"
        "\n"
        "Done. Next: uv run scripts/check.py\n"
    )
    assert captured.err == ""


def test_base_no_git(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    project = _project(tmp_path)
    runner = _create(replace(BASE, no_git=True), project)
    assert runner.calls == [
        "uv --version | .",
        "uv init --package --name demo-app --python 3.12 --vcs none | .",
        DEV_ADD,
        "uv add python-dotenv==1.2.3 | .",
    ]
    assert not (project / ".git").exists()
    captured = capsys.readouterr()
    assert captured.err == NO_HOOKS
    assert "Installing" not in captured.out
    assert captured.out.endswith("Done. Next: uv run scripts/check.py\n")


def test_base_no_install_hooks(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    runner = _create(replace(BASE, no_install_hooks=True), _project(tmp_path))
    assert not [call for call in runner.calls if "pre-commit install" in call]
    assert capsys.readouterr().err == ""


def test_base_files(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(replace(BASE, python="3.13", type_mode="strict"), project)
    files = sorted(
        path.relative_to(project).as_posix()
        for path in project.rglob("*")
        if path.is_file() and ".git" not in path.parts
    )
    assert files == [
        ".editorconfig",
        ".env.example",
        ".gitattributes",
        ".github/workflows/ci.yml",
        ".gitignore",
        ".pre-commit-config.yaml",
        ".python-version",
        "README.md",
        "pyproject.toml",
        "scripts/check.py",
        "scripts/fix.py",
        "src/demo_app/__init__.py",
        "tests/test_smoke.py",
    ]
    pyproject = (project / "pyproject.toml").read_text(encoding="utf-8")
    assert pyproject.startswith('[project]\nname = "demo-app"\n')
    assert "dependencies = []\n" in pyproject
    assert 'build-backend = "uv_build"\n[tool.ruff]\n' in pyproject
    assert 'target-version = "py313"' in pyproject
    assert 'typeCheckingMode = "strict"' in pyproject
    assert 'pythonVersion = "3.13"' in pyproject
    gitignore = (project / ".gitignore").read_text(encoding="utf-8")
    assert gitignore.startswith("# Python-generated files\n")
    assert ".venv\n# Python\n__pycache__/\n" in gitignore
    assert gitignore.endswith("Thumbs.db\n")
    assert (project / "src/demo_app/__init__.py").read_text(encoding="utf-8") == (
        'def project_name() -> str:\n    return "demo-app"\n'
    )
    assert (
        (project / "tests/test_smoke.py")
        .read_text(encoding="utf-8")
        .startswith("from demo_app import project_name\n")
    )
    readme = (project / "README.md").read_text(encoding="utf-8")
    assert readme.startswith("# demo-app\n")
    assert "Source code lives in src/demo_app/." in readme
    assert (project / "scripts/check.py").read_text(encoding="utf-8") == read_template(
        "scripts/base/check.py"
    )


def test_base_no_github_actions(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(replace(BASE, no_github_actions=True), project)
    assert not (project / ".github").exists()
    assert (project / "README.md").is_file()


def test_refuses_home(tmp_path: Path) -> None:
    runner = FakeRunner(tmp_path)
    with pytest.raises(SetupError) as info:
        create(BASE, runner, tmp_path, tmp_path)
    assert str(info.value) == (
        f"Refusing to scaffold directly in HOME: {tmp_path.resolve()}. "
        "Create and enter a project directory first."
    )
    assert runner.calls == []


def test_refuses_existing_pyproject(tmp_path: Path) -> None:
    project = _project(tmp_path)
    (project / "pyproject.toml").write_text("", encoding="utf-8")
    runner = FakeRunner(project)
    with pytest.raises(SetupError) as info:
        create(BASE, runner, project, tmp_path / "home")
    assert str(info.value) == (
        "pyproject.toml already exists. Run this only in a fresh project directory."
    )
    assert runner.calls == []


@pytest.mark.parametrize(
    ("name", "profile", "package", "project"),
    [
        ("123", "base", "123", "123"),
        ("2048 Game", "desktop", "2048_game", "2048-game"),
        ("2048", "web", "2048_backend", "2048"),
        ("class", "base", "class", "class"),
        ("import", "desktop", "import", "import"),
    ],
)
def test_refuses_invalid_package_name(
    tmp_path: Path, name: str, profile: str, package: str, project: str
) -> None:
    project_dir = _project(tmp_path)
    runner = FakeRunner(project_dir)
    with pytest.raises(SetupError) as info:
        create(replace(BASE, name=name, profile=profile), runner, project_dir, tmp_path / "home")
    assert str(info.value) == (
        f'"{package}" is not a valid Python package name (from project name "{project}"). '
        "Pass --name with a name that starts with a letter and is not a Python keyword."
    )
    assert runner.calls == []
    assert list(project_dir.iterdir()) == []


# "class_backend" is a valid package; the split layout's uv project is "<name>-backend",
# so it never clashes with a package RepoSeed installs; base does not install PySide6.
@pytest.mark.parametrize(
    ("name", "profile"),
    [("class", "web"), ("demo-2048", "base"), ("pytest", "game"), ("pyside6", "base")],
)
def test_accepts_valid_project_name(tmp_path: Path, name: str, profile: str) -> None:
    project = _project(tmp_path)
    _create(replace(BASE, name=name, profile=profile), project)
    assert (project / "README.md").is_file()


@pytest.mark.parametrize(
    ("name", "profile", "project"),
    [
        ("pytest", "base", "pytest"),
        ("Python_Dotenv", "base", "python-dotenv"),
        ("PySide6", "desktop", "pyside6"),
        ("pre-commit", "desktop", "pre-commit"),
    ],
)
def test_refuses_name_of_installed_package(
    tmp_path: Path, name: str, profile: str, project: str
) -> None:
    project_dir = _project(tmp_path)
    runner = FakeRunner(project_dir)
    with pytest.raises(SetupError) as info:
        create(replace(BASE, name=name, profile=profile), runner, project_dir, tmp_path / "home")
    assert str(info.value) == (
        f'The project name "{project}" is also the name of a package RepoSeed installs. '
        "Pass --name with a different name."
    )
    assert runner.calls == []


def test_missing_uv(tmp_path: Path) -> None:
    project = _project(tmp_path)
    runner = FakeRunner(project, missing=["uv"])
    with pytest.raises(SetupError, match="uv was not found on PATH"):
        create(BASE, runner, project, tmp_path / "home")
    assert runner.calls == []


WEB = replace(BASE, profile="web")
WEB_CALLS = [
    "uv --version | .",
    "node --version | .",
    "git init | .",
    "uv init --package --name demo-app-backend --python 3.12 --vcs none backend | .",
    "uv add python-dotenv==1.2.3 fastapi==0.141.1 uvicorn==0.54.0 | backend",
    DEV_ADD.replace("| .", "| backend"),
    "npm install --no-audit --legacy-peer-deps | frontend",
    "uv --project backend run pre-commit install --hook-type pre-push | .",
]


def test_web_calls(tmp_path: Path) -> None:
    assert _create(WEB, _project(tmp_path)).calls == WEB_CALLS


def test_web_stdout(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _create(WEB, _project(tmp_path))
    captured = capsys.readouterr()
    assert captured.out == (
        "Creating web project: demo-app (FastAPI backend, React TypeScript frontend)\n"
        "Installing pre-push hook...\n"
        "\n"
        "Done. Next: uv run scripts/check.py\n"
    )
    assert captured.err == ""


def test_web_no_git(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    project = _project(tmp_path)
    runner = _create(replace(WEB, no_git=True), project)
    assert runner.calls == [
        "uv --version | .",
        "node --version | .",
        "uv init --package --name demo-app-backend --python 3.12 --vcs none backend | .",
        "uv add python-dotenv==1.2.3 fastapi==0.141.1 uvicorn==0.54.0 | backend",
        DEV_ADD.replace("| .", "| backend"),
        "npm install --no-audit --legacy-peer-deps | frontend",
    ]
    assert not (project / ".git").exists()
    assert capsys.readouterr().err == NO_HOOKS


def test_web_missing_git(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    project = _project(tmp_path)
    runner = FakeRunner(project, missing=["git"])
    create(WEB, runner, project, tmp_path / "home")
    assert not [call for call in runner.calls if call.startswith("git")]
    assert capsys.readouterr().err == (
        "Warning: git was not found on PATH. Skipping git init.\n" + NO_HOOKS
    )


def test_web_missing_node(tmp_path: Path) -> None:
    project = _project(tmp_path)
    runner = FakeRunner(project, missing=["node"])
    with pytest.raises(SetupError, match="node and npm were not found on PATH"):
        create(WEB, runner, project, tmp_path / "home")
    assert runner.calls == ["uv --version | ."]


def test_web_files(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(replace(WEB, python="3.13", type_mode="strict"), project)
    files = sorted(
        path.relative_to(project).as_posix()
        for path in project.rglob("*")
        if path.is_file() and ".git" not in path.parts
    )
    assert files == [
        ".editorconfig",
        ".env.example",
        ".gitattributes",
        ".github/workflows/ci.yml",
        ".gitignore",
        ".pre-commit-config.yaml",
        "README.md",
        "backend/.python-version",
        "backend/README.md",
        "backend/pyproject.toml",
        "backend/src/demo_app_backend/__init__.py",
        "backend/src/demo_app_backend/main.py",
        "backend/tests/test_health.py",
        "frontend/.npmrc",
        "frontend/eslint.config.js",
        "frontend/index.html",
        "frontend/package.json",
        "frontend/src/App.test.tsx",
        "frontend/src/App.tsx",
        "frontend/src/main.tsx",
        "frontend/src/style.css",
        "frontend/src/test/setup.ts",
        "frontend/src/vite-env.d.ts",
        "frontend/tsconfig.app.json",
        "frontend/tsconfig.json",
        "frontend/tsconfig.node.json",
        "frontend/vite.config.ts",
        "scripts/check.py",
        "scripts/fix.py",
    ]
    pyproject = (project / "backend/pyproject.toml").read_text(encoding="utf-8")
    assert pyproject.startswith('[project]\nname = "demo-app-backend"\n')
    assert 'build-backend = "uv_build"\n[tool.ruff]\n' in pyproject
    assert 'target-version = "py313"' in pyproject
    assert 'typeCheckingMode = "strict"' in pyproject
    assert 'pythonVersion = "3.13"' in pyproject
    assert (project / ".gitignore").read_text(encoding="utf-8").startswith("# Python\n")
    assert (
        (project / "backend/tests/test_health.py")
        .read_text(encoding="utf-8")
        .startswith("from demo_app_backend.main import health\n")
    )
    package = (project / "frontend/package.json").read_text(encoding="utf-8")
    assert '"name": "demo-app-frontend",' in package
    assert '"node": ">=22.13.0"' in package
    assert '"react": "19.3.0",' in package
    assert '<script type="module" src="/src/main.tsx"></script>' in (
        project / "frontend/index.html"
    ).read_text(encoding="utf-8")
    readme = (project / "README.md").read_text(encoding="utf-8")
    assert "Backend source lives in backend/src/demo_app_backend/." in readme
    assert "uv --directory backend run uvicorn demo_app_backend.main:app --reload" in readme
    assert "playwright" not in readme
    assert (project / "scripts/check.py").read_text(encoding="utf-8") == read_template(
        "scripts/web/check.py"
    )


def test_playwright_installs_browser_after_npm(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setitem(PROFILES, "web", replace(PROFILES["web"], playwright=True))
    calls = _create(WEB, _project(tmp_path)).calls
    npm = calls.index("npm install --no-audit --legacy-peer-deps | frontend")
    assert calls[npm + 1] == "npm exec playwright install chromium | frontend"


GAME = replace(BASE, profile="game")
PLAYWRIGHT_INSTALL = "npm exec playwright install chromium | frontend"


def test_game_calls(tmp_path: Path) -> None:
    calls = _create(GAME, _project(tmp_path)).calls
    npm = WEB_CALLS.index("npm install --no-audit --legacy-peer-deps | frontend")
    assert calls == [*WEB_CALLS[: npm + 1], PLAYWRIGHT_INSTALL, *WEB_CALLS[npm + 1 :]]


def test_game_stdout(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _create(GAME, _project(tmp_path))
    captured = capsys.readouterr()
    assert captured.out == (
        "Creating game project: demo-app (FastAPI backend, Phaser game frontend)\n"
        "Installing pre-push hook...\n"
        "\n"
        "Done. Next: uv run scripts/check.py\n"
    )
    assert captured.err == ""


def test_game_no_git_still_installs_browser(tmp_path: Path) -> None:
    runner = _create(replace(GAME, no_git=True), _project(tmp_path))
    assert runner.calls[-2:] == [
        "npm install --no-audit --legacy-peer-deps | frontend",
        PLAYWRIGHT_INSTALL,
    ]


def test_game_files(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(GAME, project)
    files = sorted(
        path.relative_to(project).as_posix()
        for path in project.rglob("*")
        if path.is_file() and ".git" not in path.parts
    )
    assert files == [
        ".editorconfig",
        ".env.example",
        ".gitattributes",
        ".github/workflows/ci.yml",
        ".gitignore",
        ".pre-commit-config.yaml",
        "README.md",
        "backend/.python-version",
        "backend/README.md",
        "backend/pyproject.toml",
        "backend/src/demo_app_backend/__init__.py",
        "backend/src/demo_app_backend/main.py",
        "backend/tests/test_game_api.py",
        "frontend/.npmrc",
        "frontend/eslint.config.js",
        "frontend/index.html",
        "frontend/package.json",
        "frontend/playwright.config.ts",
        "frontend/src/game/GameScene.ts",
        "frontend/src/main.ts",
        "frontend/src/style.css",
        "frontend/src/vite-env.d.ts",
        "frontend/tests/game-smoke.spec.ts",
        "frontend/tsconfig.app.json",
        "frontend/tsconfig.json",
        "frontend/tsconfig.node.json",
        "frontend/vite.config.ts",
        "scripts/check.py",
        "scripts/fix.py",
    ]
    package = (project / "frontend/package.json").read_text(encoding="utf-8")
    assert '"name": "demo-app-frontend",' in package
    assert '"phaser": "' in package
    assert '"@playwright/test": "' in package
    assert "__" not in package
    assert '<script type="module" src="/src/main.ts"></script>' in (
        project / "frontend/index.html"
    ).read_text(encoding="utf-8")
    assert (
        (project / "backend/tests/test_game_api.py")
        .read_text(encoding="utf-8")
        .startswith("from demo_app_backend.main import ")
    )
    readme = (project / "README.md").read_text(encoding="utf-8")
    assert "    npm --prefix frontend exec playwright install chromium\n" in readme
    assert "uv --directory backend run uvicorn demo_app_backend.main:app --reload" in readme
    ci = (project / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert "Install Playwright Chromium" in ci
    assert "require('./package.json').scripts['test:e2e']" in ci
    assert (project / "scripts/check.py").read_text(encoding="utf-8") == read_template(
        "scripts/game/check.py"
    )


DESKTOP = replace(BASE, profile="desktop")
PYSIDE6_ADD = "uv add PySide6==6.11.2 | ."
DESKTOP_PATHS = [
    "src/demo_app/__main__.py",
    "src/demo_app/models/__init__.py",
    "src/demo_app/services/__init__.py",
    "src/demo_app/ui/__init__.py",
    "src/demo_app/ui/main_window.py",
    "tests/test_desktop_smoke.py",
]


def test_desktop_calls(tmp_path: Path) -> None:
    base = _create(BASE, _project(tmp_path / "base")).calls
    desktop = _create(DESKTOP, _project(tmp_path / "desktop")).calls
    runtime = base.index("uv add python-dotenv==1.2.3 | .")
    assert desktop == [*base[: runtime + 1], PYSIDE6_ADD, *base[runtime + 1 :]]


def test_desktop_stdout(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _create(DESKTOP, _project(tmp_path))
    captured = capsys.readouterr()
    assert captured.out == (
        "Creating Python project: demo-app "
        "(demo_app, Python 3.12, pyright standard, profile desktop)\n"
        "Adding dev tooling...\n"
        "Adding runtime dependencies...\n"
        "Installing pre-commit and pre-push hooks...\n"
        "\n"
        "Done. Next: uv run scripts/check.py\n"
    )
    assert captured.err == ""


def _text_tree(project: Path) -> dict[str, str]:
    return {path: content.decode("utf-8") for path, content in tree(project).items()}


def test_desktop_files(tmp_path: Path) -> None:
    base_project = _project(tmp_path / "base")
    desktop_project = _project(tmp_path / "desktop")
    _create(BASE, base_project)
    _create(DESKTOP, desktop_project)
    base = _text_tree(base_project)
    desktop = _text_tree(desktop_project)

    assert sorted(desktop) == sorted([*base, *DESKTOP_PATHS])
    # desktop (ported from new-project.ps1) differs from base in these shared files.
    expected = {
        **base,
        "README.md": base["README.md"]
        .replace(
            "Tests live in tests/.",
            "UI code lives in src/demo_app/ui/. Tests live in tests/.",
        )
        .replace(
            "    uv run scripts/check.py\n",
            "    uv run python -m demo_app\n    uv run scripts/check.py\n",
        ),
        "pyproject.toml": base["pyproject.toml"].replace(
            '    "tests/*"\n]', '    "tests/*",\n    "src/*/__main__.py"\n]'
        ),
        ".gitattributes": base[".gitattributes"].replace(
            "*.txt text eol=lf\n", "*.txt text eol=lf\n*.ps1 text eol=lf\n"
        ),
        ".github/workflows/ci.yml": base[".github/workflows/ci.yml"].replace(
            "      - name: Sync dependencies\n",
            "      # PySide6 imports libEGL at load time, which ubuntu-latest does not ship.\n"
            "      - name: Install system libraries\n"
            "        run: sudo apt-get update && sudo apt-get install -y libegl1\n"
            "\n"
            "      - name: Sync dependencies\n",
        ),
    }
    for path in ("README.md", "pyproject.toml", ".gitattributes", ".github/workflows/ci.yml"):
        assert expected[path] != base[path], path
    assert {path: desktop[path] for path in base} == expected

    assert desktop["README.md"].endswith(
        "## Commands\n\n"
        "Source code lives in src/demo_app/. UI code lives in src/demo_app/ui/. "
        "Tests live in tests/.\n\n"
        "    uv run python -m demo_app\n"
        "    uv run scripts/check.py\n"
        "    uv run scripts/fix.py\n"
    )
    for package in ("ui", "models", "services"):
        assert desktop[f"src/demo_app/{package}/__init__.py"] == "\n"
    assert 'self.setWindowTitle("demo-app")' in desktop["src/demo_app/ui/main_window.py"]
    assert "from demo_app.ui.main_window import MainWindow\n" in desktop["src/demo_app/__main__.py"]
    smoke = desktop["tests/test_desktop_smoke.py"]
    assert "from demo_app.ui.main_window import MainWindow\n" in smoke
    assert 'assert window.windowTitle() == "demo-app"' in smoke


def test_web_no_github_actions(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(replace(WEB, no_github_actions=True), project)
    assert not (project / ".github").exists()


@pytest.mark.parametrize("path", ["backend", "frontend", "package.json", "pyproject.toml"])
def test_web_refuses_existing_path(tmp_path: Path, path: str) -> None:
    project = _project(tmp_path)
    (project / path).mkdir()
    runner = FakeRunner(project)
    with pytest.raises(SetupError) as info:
        create(WEB, runner, project, tmp_path / "home")
    assert str(info.value) == (
        f"{path} already exists. Run this only in a fresh project directory."
    )
    assert runner.calls == []


def test_unknown_profile(tmp_path: Path) -> None:
    project = _project(tmp_path)
    runner = FakeRunner(project)
    with pytest.raises(SetupError) as info:
        create(replace(BASE, profile="nope"), runner, project, tmp_path / "home")
    assert str(info.value) == "The nope profile is not available yet."
    assert runner.calls == []


def test_missing_pin(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    versions = bundled_versions()
    del versions["PY_RUFF"]
    monkeypatch.setattr(reposeed.create, "bundled_versions", lambda: versions)
    project = _project(tmp_path)
    with pytest.raises(VersionsError) as info:
        _create(BASE, project)
    assert str(info.value) == "versions.env is missing PY_RUFF."


@pytest.mark.parametrize("name", sorted(PROFILES))
def test_profile_data_is_complete(name: str) -> None:
    profile = PROFILES[name]
    versions = bundled_versions()
    assert profile.name == name
    for add in profile.uv_adds:
        for key in add.pins:
            assert key in PIN_PACKAGES
            assert key in versions
    for spec in profile.files:
        assert read_template(spec.template)


@pytest.mark.parametrize("name", sorted(PROFILES))
def test_readmes_are_shell_neutral(tmp_path: Path, name: str) -> None:
    project = _project(tmp_path)
    _create(replace(BASE, profile=name), project)
    readme = (project / "README.md").read_text(encoding="utf-8")
    for shell_specific in ("pushd", "popd", "Push-Location", "Pop-Location"):
        assert shell_specific not in readme
    if name in ("web", "game"):
        assert (
            "    uv --directory backend run uvicorn demo_app_backend.main:app --reload\n" in readme
        )
        assert "    npm --prefix frontend run dev\n" in readme
    if name == "game":
        assert "    npm --prefix frontend exec playwright install chromium\n" in readme


def test_desktop_ci_installs_libegl1(tmp_path: Path) -> None:
    project = _project(tmp_path)
    _create(DESKTOP, project)
    ci = (project / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    install = "sudo apt-get update && sudo apt-get install -y libegl1"
    assert install in ci
    assert ci.index(install) < ci.index("uv sync")
