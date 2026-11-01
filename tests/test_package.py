import re
import sys
from pathlib import Path

import reposeed

ROOT = Path(__file__).resolve().parent.parent


def _dev_pins() -> dict[str, str]:
    text = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    if sys.version_info >= (3, 11):
        import tomllib

        entries = tomllib.loads(text)["dependency-groups"]["dev"]
    else:
        block = re.search(r"^dev\s*=\s*\[(.*?)\]", text, re.DOTALL | re.MULTILINE)
        assert block is not None
        entries = re.findall(r'"([^"]+)"', block.group(1))
    pins: dict[str, str] = {}
    for entry in entries:
        name, _, version = entry.partition("==")
        pins[name] = version
    return pins


def _versions_env() -> dict[str, str]:
    env: dict[str, str] = {}
    path = ROOT / "src" / "reposeed" / "versions.env"
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            env[key] = value
    return env


def test_version() -> None:
    assert reposeed.__version__ == "0.2.0"


def test_dev_pins_match_versions_env() -> None:
    dev = _dev_pins()
    env = _versions_env()
    assert dev["pytest"] == env["PY_PYTEST"]
    assert dev["ruff"] == env["PY_RUFF"]
    assert dev["pyright"] == env["PY_PYRIGHT"]
