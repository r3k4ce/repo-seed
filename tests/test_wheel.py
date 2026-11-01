"""The built wheel must ship the data files ``reposeed`` reads at run time."""

import shutil
import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "src" / "reposeed"


def test_wheel_ships_templates_and_versions(tmp_path: Path) -> None:
    uv = shutil.which("uv")
    if uv is None:
        pytest.skip("uv is not on PATH")
    completed = subprocess.run(
        [uv, "build", "--wheel", "--out-dir", str(tmp_path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    wheels = list(tmp_path.glob("*.whl"))
    assert len(wheels) == 1, wheels
    with zipfile.ZipFile(wheels[0]) as wheel:
        names = set(wheel.namelist())

    expected = {
        f"reposeed/{path.relative_to(PACKAGE).as_posix()}"
        for path in (PACKAGE / "templates").rglob("*")
        if path.is_file() and "__pycache__" not in path.parts
    }
    assert expected
    expected.add("reposeed/versions.env")
    assert sorted(expected - names) == []
