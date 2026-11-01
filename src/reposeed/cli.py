"""Command-line interface."""

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from reposeed import __version__
from reposeed.render import TemplateError
from reposeed.tools import CommandError, SetupError, SubprocessRunner
from reposeed.versions import VersionsError

PROFILES = ("base", "desktop", "web", "game")
TYPE_MODES = ("off", "basic", "standard", "strict")


@dataclass(frozen=True)
class Options:
    name: str
    python: str
    type_mode: str
    profile: str
    no_git: bool
    no_install_hooks: bool
    no_github_actions: bool


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="reposeed",
        allow_abbrev=False,
        description="Seed a clean, checked, agent-ready repo from the current directory.",
    )
    parser.add_argument("--name", help="Project name. Defaults to the current directory name.")
    parser.add_argument(
        "--python", default="3.12", help="Python version for uv init. Defaults to 3.12."
    )
    parser.add_argument(
        "--type-mode",
        choices=TYPE_MODES,
        default="standard",
        help="Pyright mode. Defaults to standard.",
    )
    parser.add_argument(
        "--profile",
        choices=PROFILES,
        default="base",
        help="Scaffold profile. Defaults to base.",
    )
    parser.add_argument("--no-git", action="store_true", help="Skip git initialization.")
    parser.add_argument(
        "--no-install-hooks",
        action="store_true",
        help="Skip pre-commit and pre-push hook installation.",
    )
    parser.add_argument(
        "--no-github-actions",
        action="store_true",
        help="Skip GitHub Actions workflow generation.",
    )
    parser.add_argument("--version", action="version", version=f"reposeed {__version__}")
    return parser


def parse_args(argv: Sequence[str] | None = None) -> Options:
    namespace = _parser().parse_args(argv)
    name: str | None = namespace.name
    return Options(
        name=name if name is not None else Path.cwd().name,
        python=namespace.python,
        type_mode=namespace.type_mode,
        profile=namespace.profile,
        no_git=namespace.no_git,
        no_install_hooks=namespace.no_install_hooks,
        no_github_actions=namespace.no_github_actions,
    )


def main(argv: Sequence[str] | None = None) -> int:
    options = parse_args(argv)
    from reposeed.create import create  # imported late so tests can replace it

    try:
        create(options, SubprocessRunner(), Path.cwd(), Path.home())
    except (SetupError, VersionsError, TemplateError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except CommandError as error:
        print(f"error: {error}", file=sys.stderr)
        print(
            "The project folder is incomplete; delete it and run reposeed again.",
            file=sys.stderr,
        )
        return error.code
    return 0
