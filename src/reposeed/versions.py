"""Reader for the pinned tool versions in ``versions.env``."""

import re
from importlib.resources import files

_LINE = re.compile(r"([A-Z][A-Z0-9_]*)=([A-Za-z0-9.+-]+)")


class VersionsError(ValueError):
    """Raised when ``versions.env`` contains a malformed line."""


def load_versions(text: str) -> dict[str, str]:
    """Parse ``KEY=value`` lines; ``#`` starts a comment and whitespace is ignored."""
    versions: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.partition("#")[0].strip()
        if not line:
            continue
        match = _LINE.fullmatch("".join(line.split()))
        if match is None:
            raise VersionsError(f"Invalid line in versions.env: {line}")
        versions[match.group(1)] = match.group(2)
    return versions


def bundled_versions() -> dict[str, str]:
    """Load the ``versions.env`` shipped inside the package."""
    text = (files("reposeed") / "versions.env").read_text(encoding="utf-8")
    return load_versions(text)
