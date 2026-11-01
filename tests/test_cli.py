from pathlib import Path

import pytest

import reposeed.create
from reposeed.cli import Options, main, parse_args
from reposeed.render import TemplateError
from reposeed.tools import CommandError, SetupError
from reposeed.versions import VersionsError

INCOMPLETE = "The project folder is incomplete; delete it and run reposeed again."


def test_parse_args_defaults(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    folder = tmp_path / "My App"
    folder.mkdir()
    monkeypatch.chdir(folder)
    assert parse_args([]) == Options(
        name="My App",
        python="3.12",
        type_mode="standard",
        profile="base",
        no_git=False,
        no_install_hooks=False,
        no_github_actions=False,
    )


def test_parse_args_all_options() -> None:
    options = parse_args(
        [
            "--name",
            "demo",
            "--python",
            "3.13",
            "--type-mode",
            "strict",
            "--profile",
            "desktop",
            "--no-git",
            "--no-install-hooks",
            "--no-github-actions",
        ]
    )
    assert options == Options("demo", "3.13", "strict", "desktop", True, True, True)


@pytest.mark.parametrize("profile", ["base", "desktop", "web", "game"])
def test_parse_args_profiles(profile: str) -> None:
    assert parse_args(["--profile", profile]).profile == profile


@pytest.mark.parametrize(
    "argv",
    [
        ["--profile", "nope"],
        ["--type-mode", "loose"],
        ["-Profile", "web"],
        ["--bogus"],
        ["--prof", "web"],
    ],
)
def test_parse_args_rejects_invalid(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as info:
        parse_args(argv)
    assert info.value.code == 2


def test_version_flag(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as info:
        parse_args(["--version"])
    assert info.value.code == 0
    assert capsys.readouterr().out.strip() == "reposeed 0.2.0"


def test_help_flag(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as info:
        parse_args(["-h"])
    assert info.value.code == 0
    assert "--no-github-actions" in capsys.readouterr().out


def test_main_success(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: list[Options] = []

    def fake_create(options: Options, runner: object, cwd: Path, home: Path) -> None:
        seen.append(options)
        assert cwd == Path.cwd()
        assert home == Path.home()

    monkeypatch.setattr(reposeed.create, "create", fake_create)
    assert main(["--name", "demo"]) == 0
    assert seen[0].name == "demo"


@pytest.mark.parametrize(
    ("error", "code", "message"),
    [
        (SetupError("uv was not found on PATH."), 1, "error: uv was not found on PATH.\n"),
        (VersionsError("bad line"), 1, "error: bad line\n"),
        (TemplateError("unfilled __X__"), 1, "error: unfilled __X__\n"),
        (
            CommandError(["uv", "add", "--dev", "pytest==9.1.1"], 7),
            7,
            f"error: 'uv add --dev pytest==9.1.1' failed with exit code 7\n{INCOMPLETE}\n",
        ),
    ],
)
def test_main_maps_errors(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    error: Exception,
    code: int,
    message: str,
) -> None:
    def failing_create(options: Options, runner: object, cwd: Path, home: Path) -> None:
        raise error

    monkeypatch.setattr(reposeed.create, "create", failing_create)
    assert main([]) == code
    captured = capsys.readouterr()
    assert captured.err == message
    assert captured.out == ""
    assert "Traceback" not in captured.err
