# __PROJECT_NAME__

## Setup

    uv sync --dev

Copy .env.example to .env only when real secrets are needed. Never commit .env.

Dependencies are pinned to exact versions. To upgrade one, change its version
in pyproject.toml, run uv lock, then run the checks.

## Commands

Source code lives in src/__PACKAGE_NAME__/. Tests live in tests/.

    uv run scripts/check.py
    uv run scripts/fix.py
