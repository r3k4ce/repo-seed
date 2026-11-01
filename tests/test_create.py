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
from tests.fakes import FakeRunner

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
    project.mkdir()
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
    runner = _create(replace(BASE, no_git=True), _project(tmp_path))
    assert runner.calls == [
        "uv --version | .",
        "uv init --package --name demo-app --python 3.12 --vcs none | .",
        DEV_ADD,
        "uv add python-dotenv==1.2.3 | .",
    ]
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


def test_missing_uv(tmp_path: Path) -> None:
    project = _project(tmp_path)
    runner = FakeRunner(project, missing=["uv"])
    with pytest.raises(SetupError, match="uv was not found on PATH"):
        create(BASE, runner, project, tmp_path / "home")
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
