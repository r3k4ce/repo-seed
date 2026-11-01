"""Project creation (stub; implemented in a later task)."""

from pathlib import Path
from typing import TYPE_CHECKING

from reposeed.tools import Runner

if TYPE_CHECKING:
    from reposeed.cli import Options


def create(options: "Options", runner: Runner, cwd: Path, home: Path) -> None:
    raise NotImplementedError
