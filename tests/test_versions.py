import re

import pytest

from reposeed.profiles import PIN_PACKAGES
from reposeed.versions import VersionsError, bundled_versions, load_versions


def test_load_versions_parses_pairs_comments_and_blanks() -> None:
    text = "# header\n\nPY_RUFF=0.16.9\nNODE_X = 1.2.3+build-1  # trailing\n"
    assert load_versions(text) == {"PY_RUFF": "0.16.9", "NODE_X": "1.2.3+build-1"}


def test_load_versions_rejects_bad_line() -> None:
    with pytest.raises(VersionsError, match=re.escape("Invalid line in versions.env: bad line")):
        load_versions("PY_RUFF=1\nbad line\n")


def test_load_versions_rejects_bad_value() -> None:
    with pytest.raises(VersionsError, match=r"Invalid line in versions\.env"):
        load_versions("PY_RUFF=1;2\n")


def test_bundled_versions_has_every_key() -> None:
    assert {"UV_MIN", "NODE_MIN", *PIN_PACKAGES} <= bundled_versions().keys()
