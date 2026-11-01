"""Project creation: runs one profile from ``profiles.py`` in the current folder."""

import keyword
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import TYPE_CHECKING

from reposeed.naming import package_name, project_name, ruff_target
from reposeed.profiles import PIN_PACKAGES, PROFILES, Profile, UvAdd
from reposeed.render import append_file, read_template, render, write_file
from reposeed.tools import Runner, SetupError, require_node, require_uv
from reposeed.versions import VersionsError, bundled_versions

if TYPE_CHECKING:
    from reposeed.cli import Options

DONE = "Done. Next: uv run scripts/check.py"

# Folders of the split layout, relative to the project root.
BACKEND = "backend"
FRONTEND = "frontend"

# Message and commands (run from the project root) for each hook style.
_HOOKS: dict[str, tuple[str, tuple[tuple[str, ...], ...]]] = {
    "per_tool": (
        "Installing pre-commit and pre-push hooks...",
        (
            ("uv", "run", "pre-commit", "install"),
            ("uv", "run", "pre-commit", "install", "--hook-type", "pre-push"),
        ),
    ),
    "pre_push": (
        "Installing pre-push hook...",
        (
            (
                "uv",
                "--project",
                BACKEND,
                "run",
                "pre-commit",
                "install",
                "--hook-type",
                "pre-push",
            ),
        ),
    ),
}


def _say(message: str) -> None:
    # Flush so our lines stay in order with the output of the tools we run.
    print(message, flush=True)


def _warn(message: str) -> None:
    print(f"Warning: {message}", file=sys.stderr, flush=True)


def _pin(versions: Mapping[str, str], key: str) -> str:
    if key not in versions:
        raise VersionsError(f"versions.env is missing {key}.")
    return versions[key]


def _context(profile: Profile, options: "Options", versions: Mapping[str, str]) -> dict[str, str]:
    project = project_name(options.name)
    package = package_name(project)
    context = {
        "PROFILE": profile.name,
        "PROJECT_NAME": project,
        "PACKAGE_NAME": package,
        "BACKEND_PACKAGE_NAME": f"{package}_{BACKEND}",
        "PYTHON_VERSION": options.python,
        "RUFF_TARGET": ruff_target(options.python),
        "TYPE_MODE": options.type_mode,
    }
    context.update({f"PIN_{key}": value for key, value in versions.items()})
    return context


def _check_folder(profile: Profile, root: Path, home: Path) -> None:
    resolved_home = home.resolve()
    if root.resolve() == resolved_home:
        raise SetupError(
            f"Refusing to scaffold directly in HOME: {resolved_home}. "
            "Create and enter a project directory first."
        )
    for path in profile.fresh_paths:
        if (root / path).exists():
            raise SetupError(f"{path} already exists. Run this only in a fresh project directory.")


def _check_names(profile: Profile, project: str) -> None:
    """Refuse names that would generate a project unable to import or install itself."""
    if profile.layout == "single":
        uv_project, package = project, package_name(project)
    else:
        uv_project, package = f"{project}-{BACKEND}", f"{package_name(project)}_{BACKEND}"
    if not package.isidentifier() or keyword.iskeyword(package):
        raise SetupError(
            f'"{package}" is not a valid Python package name (from project name "{project}"). '
            "Pass --name with a name that starts with a letter and is not a Python keyword."
        )
    installed = {project_name(PIN_PACKAGES[key]) for add in profile.uv_adds for key in add.pins}
    if uv_project in installed:
        raise SetupError(
            f'The project name "{uv_project}" is also the name of a package RepoSeed installs. '
            "Pass --name with a different name."
        )


def _uv_add_command(add: UvAdd, versions: Mapping[str, str]) -> list[str]:
    pins = [f"{PIN_PACKAGES[key]}=={_pin(versions, key)}" for key in add.pins]
    return ["uv", "add", *(["--dev"] if add.dev else []), *pins]


def _write_files(
    profile: Profile, options: "Options", context: Mapping[str, str], root: Path
) -> None:
    for spec in profile.files:
        if spec.when == "github_actions" and options.no_github_actions:
            continue
        text = render(read_template(spec.template), context, source=spec.template)
        path = root / render(spec.dest, context, source=spec.dest)
        if spec.mode == "append":
            append_file(path, text)
        else:
            write_file(path, text)


def _install_hooks(profile: Profile, options: "Options", runner: Runner, root: Path) -> None:
    if options.no_install_hooks:
        return
    if not (root / ".git").is_dir():
        _warn("No .git directory found. Skipping hook installation.")
        return
    message, commands = _HOOKS[profile.hooks]
    _say(message)
    for command in commands:
        runner.run(command, root)


def _python_dir(profile: Profile, root: Path) -> Path:
    """Folder holding the uv project: the root, or ``backend/`` in the split layout."""
    return root if profile.layout == "single" else root / BACKEND


def _init_python(
    profile: Profile, options: "Options", project: str, runner: Runner, root: Path
) -> None:
    init = ["uv", "init", "--package", "--name"]
    if profile.layout == "single":
        init += [project, "--python", options.python]
        if options.no_git:
            init += ["--vcs", "none"]
    else:
        # The repository is the root folder, so git is set up here, not by uv.
        if not options.no_git:
            if runner.which("git") is None:
                _warn("git was not found on PATH. Skipping git init.")
            else:
                runner.run(["git", "init"], root)
        init += [f"{project}-{BACKEND}", "--python", options.python, "--vcs", "none", BACKEND]
    runner.run(init, root)


def _install_frontend(profile: Profile, runner: Runner, root: Path) -> None:
    frontend = root / FRONTEND
    if profile.npm_install:
        runner.run(["npm", "install", "--no-audit", "--legacy-peer-deps"], frontend)
    if profile.playwright:
        runner.run(["npm", "exec", "playwright", "install", "chromium"], frontend)


def create(options: "Options", runner: Runner, cwd: Path, home: Path) -> None:
    profile = PROFILES.get(options.profile)
    if profile is None:
        raise SetupError(f"The {options.profile} profile is not available yet.")
    _check_folder(profile, cwd, home)
    _check_names(profile, project_name(options.name))

    versions = bundled_versions()
    require_uv(runner, _pin(versions, "UV_MIN"))
    if profile.needs_node:
        require_node(runner, _pin(versions, "NODE_MIN"), profile.name)

    context = _context(profile, options, versions)
    _say(render(profile.header, context, source=f"{profile.name} header"))

    _init_python(profile, options, context["PROJECT_NAME"], runner, cwd)
    python_dir = _python_dir(profile, cwd)
    for add in profile.uv_adds:
        if add.message:
            _say(add.message)
        runner.run(_uv_add_command(add, versions), python_dir)

    _write_files(profile, options, context, cwd)
    _install_frontend(profile, runner, cwd)
    _install_hooks(profile, options, runner, cwd)
    _say(f"\n{DONE}")
