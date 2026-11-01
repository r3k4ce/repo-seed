from pathlib import Path

import pytest

from reposeed.render import TemplateError, append_file, read_template, render, write_file

TEMPLATES = Path(__file__).resolve().parent.parent / "src" / "reposeed" / "templates"


def test_render_replaces_known_tokens() -> None:
    assert render("a __PROJECT_NAME__ b", {"PROJECT_NAME": "x"}, source="t") == "a x b"


def test_render_leaves_dunders_and_github_expressions() -> None:
    text = "__init__ __name__ __file__ ${{ secrets.X }}"
    assert render(text, {}, source="t") == text


def test_render_token_followed_by_underscore_text() -> None:
    # Bash replaces the literal __PACKAGE_NAME__ inside __PACKAGE_NAME___backend.
    text = "from __PACKAGE_NAME___backend.main import x"
    assert render(text, {"PACKAGE_NAME": "demo"}, source="t") == "from demo_backend.main import x"


def test_render_unknown_token_raises() -> None:
    with pytest.raises(TemplateError) as info:
        render("x __NOT_A_KEY__ y", {"PROJECT_NAME": "x"}, source="t")
    assert "t" in str(info.value)
    assert "__NOT_A_KEY__" in str(info.value)


def test_render_does_not_rescan_substituted_values() -> None:
    assert render("__A__", {"A": "__B__", "B": "no"}, source="t") == "__B__"


def test_read_template() -> None:
    expected = (TEMPLATES / "scripts" / "base" / "check.py").read_text(encoding="utf-8")
    assert read_template("scripts/base/check.py") == expected
    assert expected


def test_write_file_normalizes_and_creates_parents(tmp_path: Path) -> None:
    target = tmp_path / "a" / "b" / "f.txt"
    write_file(target, "a\r\nb\n\n\n")
    assert target.read_bytes() == b"a\nb\n"


def test_write_file_cr_only_and_no_bom(tmp_path: Path) -> None:
    target = tmp_path / "f.txt"
    write_file(target, "é\rx")
    assert target.read_bytes() == "é\nx\n".encode()


@pytest.mark.parametrize(
    ("existing", "appended", "expected"),
    [
        ("a\n", "\nb", "a\nb\n"),
        ("a", "b", "a\nb\n"),
        ("  \n", "b", "b\n"),
        ("", "b", "b\n"),
        ("a\r\nb\r\n", "c", "a\nb\nc\n"),
        # Bash `$(<file)` strips every trailing newline of the existing text.
        ("a\n\n", "b\n", "a\nb\n"),
        ("a\n\n\n", "\n\nb\n\n", "a\nb\n"),
    ],
)
def test_append_file_matches_add_text_file(
    tmp_path: Path, existing: str, appended: str, expected: str
) -> None:
    target = tmp_path / "f.txt"
    target.write_bytes(existing.encode())
    append_file(target, appended)
    assert target.read_bytes() == expected.encode()


def test_append_file_missing_file_behaves_like_write(tmp_path: Path) -> None:
    target = tmp_path / "x" / "f.txt"
    append_file(target, "\n\nb\r\n\n")
    assert target.read_bytes() == b"b\n"
