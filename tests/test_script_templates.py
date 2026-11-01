"""Contract for the generated scripts/check.py and scripts/fix.py templates.

Each template runs as a real subprocess against fake ``uv`` and ``npm`` tools,
written in Python and placed alone on PATH. Every fake logs
``<tool> <args> | cwd=<folder name> | venv=<VIRTUAL_ENV or unset>`` and exits 3
when ``<tool> <args>`` equals ``$FAKE_FAIL_ON``.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from reposeed.profiles import PROFILES as SCAFFOLD_PROFILES

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "src" / "reposeed" / "templates" / "scripts"
PROFILES = ("base", "web", "game")
TASKS = ("check", "fix")
CASES = [(profile, task) for profile in PROFILES for task in TASKS]
CASE_IDS = [f"{profile}-{task}" for profile, task in CASES]

HELPER_START = "# --- shared helper ---"
HELPER_END = "# --- end shared helper ---"

FAKE_TOOL = """\
import os
import sys
from pathlib import Path

line = " ".join([{tool!r}, *sys.argv[1:]])
venv = os.environ.get("VIRTUAL_ENV", "unset")
with open({log!r}, "a", encoding="utf-8") as log:
    log.write(f"{{line}} | cwd={{Path.cwd().name}} | venv={{venv}}\\n")
fail_on = os.environ.get("FAKE_FAIL_ON", "")
sys.exit(3 if fail_on and line == fail_on else 0)
"""


def _fake_tools(case_dir: Path, tools: tuple[str, ...] = ("uv", "npm")) -> tuple[Path, Path]:
    """Write the fakes and return the folder to put on PATH and the call log."""
    bin_dir = case_dir / "bin"
    source_dir = case_dir / "fakes"  # Kept off PATH so a .PY in PATHEXT cannot match.
    log = case_dir / "calls.log"
    bin_dir.mkdir(parents=True)
    source_dir.mkdir()
    log.write_text("", encoding="utf-8")
    for tool in tools:
        body = FAKE_TOOL.format(tool=tool, log=str(log))
        if sys.platform == "win32":
            source = source_dir / f"{tool}.py"
            source.write_text(body, encoding="utf-8")
            shim = f'@"{sys.executable}" "{source}" %*\r\n@exit /b %errorlevel%\r\n'
            (bin_dir / f"{tool}.cmd").write_text(shim, encoding="utf-8")
        else:
            script = bin_dir / tool
            script.write_text(f"#!{sys.executable}\n{body}", encoding="utf-8")
            script.chmod(0o755)
    return bin_dir, log


def _project(case_dir: Path, profile: str, task: str) -> Path:
    project = case_dir / "project"
    (project / "scripts").mkdir(parents=True)
    (project / "backend").mkdir()
    (project / "frontend").mkdir()
    shutil.copyfile(TEMPLATES / profile / f"{task}.py", project / "scripts" / f"{task}.py")
    return project


def _run(
    bin_dir: Path, project: Path, task: str, fail_on: str = ""
) -> subprocess.CompletedProcess[str]:
    """Run a template from backend/ with only the fakes on PATH and a caller VIRTUAL_ENV."""
    env = {"PATH": str(bin_dir), "VIRTUAL_ENV": "/caller/venv", "FAKE_FAIL_ON": fail_on}
    # Windows needs these to start Python and to run .cmd shims.
    for name in ("SYSTEMROOT", "COMSPEC", "PATHEXT"):
        if name in os.environ:
            env[name] = os.environ[name]
    return subprocess.run(
        [sys.executable, str(project / "scripts" / f"{task}.py")],
        cwd=project / "backend",
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _calls(log: Path) -> list[str]:
    return log.read_text(encoding="utf-8").splitlines()


def _expected_steps(profile: str, task: str, project_name: str) -> list[str]:
    python_cwd = project_name if profile == "base" else "backend"
    if task == "check":
        python_steps = ["uv run ruff format --check .", "uv run ruff check ."]
    else:
        python_steps = ["uv run ruff check . --fix", "uv run ruff format .", "uv run ruff check ."]
    python_steps += ["uv run pyright", "uv run pytest"]
    npm_steps = {
        "base": [],
        "web": ["npm run test", "npm run typecheck", "npm run lint", "npm run build"],
        "game": [
            "npm run test --if-present",
            "npm run test:e2e --if-present",
            "npm run lint",
            "npm run build",
        ],
    }[profile]
    return [f"{step} | cwd={python_cwd} | venv=unset" for step in python_steps] + [
        f"{step} | cwd=frontend | venv=unset" for step in npm_steps
    ]


@pytest.mark.parametrize(("profile", "task"), CASES, ids=CASE_IDS)
def test_template_exists(profile: str, task: str) -> None:
    assert (TEMPLATES / profile / f"{task}.py").is_file()


def test_every_profile_uses_a_tested_template() -> None:
    # desktop has no scripts/desktop/; it ships the base scripts, covered as "base" here.
    tested = {f"scripts/{profile}/{task}.py" for profile, task in CASES}
    for profile in SCAFFOLD_PROFILES.values():
        scripts = {spec.template for spec in profile.files if spec.dest.startswith("scripts/")}
        assert scripts <= tested, profile.name
    desktop = SCAFFOLD_PROFILES["desktop"].files
    assert {spec.template for spec in desktop if spec.dest.startswith("scripts/")} == {
        "scripts/base/check.py",
        "scripts/base/fix.py",
    }


# The scaffolder writes LF and the e2e tests compare generated scripts to the
# templates byte for byte, so a Windows checkout must not convert them to CRLF.
@pytest.mark.skipif(shutil.which("git") is None, reason="needs git")
@pytest.mark.parametrize(("profile", "task"), CASES, ids=CASE_IDS)
def test_template_checks_out_with_lf(profile: str, task: str) -> None:
    path = f"src/reposeed/templates/scripts/{profile}/{task}.py"
    completed = subprocess.run(
        ["git", "check-attr", "eol", "--", path],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    assert completed.stdout.strip() == f"{path}: eol: lf"


def _shared_helper(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    assert HELPER_START in lines, f"No shared helper block in {path}"
    assert HELPER_END in lines, f"No shared helper block in {path}"
    return lines[lines.index(HELPER_START) : lines.index(HELPER_END) + 1]


def test_shared_helper_identical() -> None:
    reference = _shared_helper(TEMPLATES / "base" / "check.py")
    for profile, task in CASES:
        assert _shared_helper(TEMPLATES / profile / f"{task}.py") == reference, (profile, task)


@pytest.mark.parametrize(("profile", "task"), CASES, ids=CASE_IDS)
def test_steps(tmp_path: Path, profile: str, task: str) -> None:
    bin_dir, log = _fake_tools(tmp_path)
    project = _project(tmp_path, profile, task)

    completed = _run(bin_dir, project, task)

    assert completed.returncode == 0, completed.stderr
    assert _calls(log) == _expected_steps(profile, task, project.name)


def test_stops_at_first_failure(tmp_path: Path) -> None:
    bin_dir, log = _fake_tools(tmp_path)
    project = _project(tmp_path, "base", "check")

    completed = _run(bin_dir, project, "check", fail_on="uv run ruff check .")

    assert completed.returncode == 3
    assert _calls(log) == _expected_steps("base", "check", project.name)[:2]


def test_missing_tool(tmp_path: Path) -> None:
    bin_dir, log = _fake_tools(tmp_path, tools=("uv",))
    project = _project(tmp_path, "web", "check")

    completed = _run(bin_dir, project, "check")

    assert completed.returncode != 0
    assert "error: 'npm' was not found on PATH" in completed.stderr
    assert "Traceback" not in completed.stderr
    assert _calls(log) == _expected_steps("web", "check", project.name)[:4]


def test_prints_commands(tmp_path: Path) -> None:
    bin_dir, _ = _fake_tools(tmp_path)
    project = _project(tmp_path, "base", "check")

    completed = _run(bin_dir, project, "check")

    assert completed.returncode == 0, completed.stderr
    assert "> uv run ruff format --check ." in completed.stdout
    assert "> uv run pytest" in completed.stdout
