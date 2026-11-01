"""Template rendering and normalized file writing."""

import re
from collections.abc import Mapping
from importlib.resources import files
from pathlib import Path

_TOKEN = re.compile(r"__[A-Z][A-Z0-9_]*__")
_SPACE = " \t\n\v\f\r"


class TemplateError(ValueError):
    """Raised when a template still has an unreplaced ``__TOKEN__`` after rendering."""


def read_template(name: str) -> str:
    """Return the text of a bundled template, e.g. ``scripts/base/check.py``."""
    resource = files("reposeed") / "templates"
    for part in name.split("/"):
        resource = resource / part
    return resource.read_text(encoding="utf-8")


def render(text: str, context: Mapping[str, str], *, source: str) -> str:
    """Replace every ``__KEY__`` found in ``context``; any other token is an error."""
    unknown: list[str] = []

    def substitute(match: re.Match[str]) -> str:
        token = match.group(0)
        key = token[2:-2]
        if key in context:
            return context[key]
        if token not in unknown:
            unknown.append(token)
        return token

    rendered = _TOKEN.sub(substitute, text)
    if unknown:
        raise TemplateError(f"Unreplaced placeholder in {source}: {', '.join(unknown)}")
    return rendered


def _lf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _store(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((text.rstrip("\n") + "\n").encode("utf-8"))


def write_file(path: Path, text: str) -> None:
    """Write ``text`` as UTF-8 with LF endings and exactly one trailing newline."""
    _store(path, _lf(text))


def append_file(path: Path, text: str) -> None:
    """Append ``text`` to ``path`` the way ``add_text_file`` in new-project.sh does."""
    addition = _lf(text).lstrip("\n")
    if not path.is_file():
        write_file(path, addition)
        return
    # Bash `$(<file)` drops every trailing newline of the existing content.
    existing = _lf(path.read_bytes().decode("utf-8")).rstrip("\n")
    if not existing.strip(_SPACE):
        _store(path, addition)
        return
    _store(path, existing + "\n" + addition)
