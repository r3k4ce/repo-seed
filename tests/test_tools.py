from collections.abc import Sequence
from pathlib import Path

import pytest

from reposeed.tools import (
    CommandError,
    SetupError,
    SubprocessRunner,
    extract_version,
    require_node,
    require_uv,
    version_at_least,
)


class StubRunner:
    def __init__(self, tools: dict[str, str], outputs: dict[str, str] | None = None) -> None:
        self.tools = tools
        self.outputs = outputs or {}

    def run(self, command: Sequence[str], cwd: Path) -> None:
        raise AssertionError("run must not be called")

    def which(self, name: str) -> str | None:
        return self.tools.get(name)

    def output(self, command: Sequence[str]) -> str:
        return self.outputs.get(command[0], "")


def test_version_at_least() -> None:
    assert version_at_least("0.13.3", "0.5.0")
    assert not version_at_least("21.9.0", "22.13.0")
    assert version_at_least("22.13.0", "22.13.0")
    assert version_at_least("1.10", "1.9.9")


def test_extract_version() -> None:
    assert extract_version("uv 0.13.3 (x86_64-unknown-linux-gnu)") == "0.13.3"
    assert extract_version("v22.13.0") == "22.13.0"
    assert extract_version("no digits") is None


def test_require_uv_missing() -> None:
    with pytest.raises(SetupError) as info:
        require_uv(StubRunner({}), "0.5.0")
    assert str(info.value) == "uv was not found on PATH. Install uv first, then rerun this script."


def test_require_uv_unreadable_version() -> None:
    runner = StubRunner({"uv": "/bin/uv"}, {"uv": "garbage"})
    with pytest.raises(SetupError) as info:
        require_uv(runner, "0.5.0")
    assert str(info.value) == "Could not read the uv version from 'uv --version'."


def test_require_uv_too_old() -> None:
    runner = StubRunner({"uv": "/bin/uv"}, {"uv": "uv 0.4.0"})
    with pytest.raises(SetupError) as info:
        require_uv(runner, "0.5.0")
    assert str(info.value) == (
        "uv 0.4.0 is too old. RepoSeed needs uv 0.5.0 or newer. Run 'uv self update' and retry."
    )


def test_require_uv_ok() -> None:
    require_uv(StubRunner({"uv": "/bin/uv"}, {"uv": "uv 0.13.3 (abc)"}), "0.5.0")


@pytest.mark.parametrize("tools", [{}, {"node": "/bin/node"}, {"npm": "/bin/npm"}])
def test_require_node_missing(tools: dict[str, str]) -> None:
    with pytest.raises(SetupError) as info:
        require_node(StubRunner(tools), "22.13.0", "web")
    assert str(info.value) == (
        "node and npm were not found on PATH. Install Node.js first, then rerun this script."
    )


def test_require_node_unreadable_version() -> None:
    runner = StubRunner({"node": "/bin/node", "npm": "/bin/npm"}, {"node": ""})
    with pytest.raises(SetupError) as info:
        require_node(runner, "22.13.0", "web")
    assert str(info.value) == "Could not read the Node.js version from 'node --version'."


def test_require_node_too_old() -> None:
    runner = StubRunner({"node": "/bin/node", "npm": "/bin/npm"}, {"node": "v21.0.0"})
    with pytest.raises(SetupError) as info:
        require_node(runner, "22.13.0", "web")
    assert str(info.value) == (
        "Node.js 21.0.0 is too old. RepoSeed needs Node.js 22.13.0 or newer for the web profile."
    )


def test_require_node_ok() -> None:
    runner = StubRunner({"node": "/bin/node", "npm": "/bin/npm"}, {"node": "v22.13.0"})
    require_node(runner, "22.13.0", "game")


def test_command_error_fields() -> None:
    error = CommandError(["uv", "init"], 3)
    assert error.command == ("uv", "init")
    assert error.code == 3


def test_subprocess_runner_missing_tool(tmp_path: Path) -> None:
    with pytest.raises(SetupError) as info:
        SubprocessRunner().run(["definitely-not-a-real-tool-xyz"], tmp_path)
    assert str(info.value) == "'definitely-not-a-real-tool-xyz' was not found on PATH."


def test_subprocess_runner_run_and_failure(tmp_path: Path) -> None:
    import sys

    runner = SubprocessRunner()
    runner.run([sys.executable, "-c", "import sys; sys.exit(0)"], tmp_path)
    with pytest.raises(CommandError) as info:
        runner.run([sys.executable, "-c", "import sys; sys.exit(7)"], tmp_path)
    assert info.value.code == 7
    assert info.value.command[1:] == ("-c", "import sys; sys.exit(7)")


def test_subprocess_runner_output_and_which() -> None:
    import sys

    runner = SubprocessRunner()
    assert runner.output([sys.executable, "-c", "print('hi')"]).strip() == "hi"
    assert runner.output(["definitely-not-a-real-tool-xyz"]) == ""
    assert runner.which("definitely-not-a-real-tool-xyz") is None
