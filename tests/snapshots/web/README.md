# demo-app

## Setup

    pushd backend >/dev/null; uv sync --dev; popd >/dev/null
    pushd frontend >/dev/null; npm install; popd >/dev/null

Copy .env.example to .env only when real secrets are needed. Never commit .env.

Dependencies are pinned to exact versions. To upgrade one, change its version
in backend/pyproject.toml (then run uv lock) or frontend/package.json (then run
npm install), and run the checks.

## Commands

Backend source lives in backend/src/demo_app_backend/. Frontend source lives in frontend/src/.

    uv run scripts/check.py
    uv run scripts/fix.py
    pushd backend >/dev/null; uv run uvicorn demo_app_backend.main:app --reload; popd >/dev/null
    pushd frontend >/dev/null; npm run dev; popd >/dev/null
