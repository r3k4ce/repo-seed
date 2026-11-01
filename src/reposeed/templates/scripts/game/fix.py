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

BACKEND = ROOT / "backend"
FRONTEND = ROOT / "frontend"


def main() -> None:
    run("uv", "run", "ruff", "check", ".", "--fix", cwd=BACKEND)
    run("uv", "run", "ruff", "format", ".", cwd=BACKEND)
    run("uv", "run", "ruff", "check", ".", cwd=BACKEND)
    run("uv", "run", "pyright", cwd=BACKEND)
    run("uv", "run", "pytest", cwd=BACKEND)
    run("npm", "run", "test", "--if-present", cwd=FRONTEND)
    run("npm", "run", "test:e2e", "--if-present", cwd=FRONTEND)
    run("npm", "run", "lint", cwd=FRONTEND)
    run("npm", "run", "build", cwd=FRONTEND)


if __name__ == "__main__":
    main()
