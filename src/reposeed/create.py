"""Project creation: runs one profile from ``profiles.py`` in the current folder."""

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

# Message and commands (run from the project root) for each hook style.
_HOOKS: dict[str, tuple[str, tuple[str, ...]]] = {
    "per_tool": (
        "Installing pre-commit and pre-push hooks...",
        (
            "uv run pre-commit install",
            "uv run pre-commit install --hook-type pre-push",
        ),
    ),
    "pre_push": (
        "Installing pre-push hook...",
        ("uv --project backend run pre-commit install --hook-type pre-push",),
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


def _context(options: "Options", versions: Mapping[str, str]) -> dict[str, str]:
    project = project_name(options.name)
    package = package_name(project)
    context = {
        "PROJECT_NAME": project,
        "PACKAGE_NAME": package,
        "BACKEND_PACKAGE_NAME": f"{package}_backend",
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
        runner.run(command.split(), root)


def create(options: "Options", runner: Runner, cwd: Path, home: Path) -> None:
    profile = PROFILES.get(options.profile)
    if profile is None:
        raise SetupError(f"The {options.profile} profile is not available yet.")
    _check_folder(profile, cwd, home)

    versions = bundled_versions()
    require_uv(runner, _pin(versions, "UV_MIN"))
    if profile.needs_node:
        require_node(runner, _pin(versions, "NODE_MIN"), profile.name)

    context = _context(options, versions)
    project, package = context["PROJECT_NAME"], context["PACKAGE_NAME"]
    _say(
        f"Creating Python project: {project} ({package}, Python {options.python}, "
        f"pyright {options.type_mode}, profile {options.profile})"
    )

    init = ["uv", "init", "--package", "--name", project, "--python", options.python]
    if options.no_git:
        init += ["--vcs", "none"]
    runner.run(init, cwd)

    for add in profile.uv_adds:
        if add.message:
            _say(add.message)
        runner.run(_uv_add_command(add, versions), cwd)

    _write_files(profile, options, context, cwd)
    _install_hooks(profile, options, runner, cwd)
    _say(f"\n{DONE}")
