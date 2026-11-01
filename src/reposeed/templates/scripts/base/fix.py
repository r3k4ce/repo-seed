# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Apply automatic fixes, then run the checks. Usage: uv run scripts/fix.py"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# --- shared helper ---
def run(*command: str, cwd: Path = ROOT) -> None:
    executable = shutil.which(command[0])
    if executable is None:
        sys.exit(f"error: '{command[0]}' was not found on PATH")
    env = {key: value for key, value in os.environ.items() if key != "VIRTUAL_ENV"}
    print(f"> {' '.join(command)}", flush=True)
    result = subprocess.run([executable, *command[1:]], cwd=cwd, env=env, check=False)
    if result.returncode != 0:
        sys.exit(result.returncode)


# --- end shared helper ---


def main() -> None:
    run("uv", "run", "ruff", "check", ".", "--fix")
    run("uv", "run", "ruff", "format", ".")
    run("uv", "run", "ruff", "check", ".")
    run("uv", "run", "pyright")
    run("uv", "run", "pytest")


if __name__ == "__main__":
    main()
