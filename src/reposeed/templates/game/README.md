# __PROJECT_NAME__

## Setup

    uv --directory backend sync --dev
    npm --prefix frontend install
    npm --prefix frontend exec playwright install chromium

Copy .env.example to .env only when real secrets are needed. Never commit .env.

Dependencies are pinned to exact versions. To upgrade one, change its version
in backend/pyproject.toml (then run uv lock) or frontend/package.json (then run
npm install), and run the checks.

## Commands

Backend source lives in backend/src/__BACKEND_PACKAGE_NAME__/. Frontend source lives in frontend/src/.

    uv run scripts/check.py
    uv run scripts/fix.py
    uv --directory backend run uvicorn __BACKEND_PACKAGE_NAME__.main:app --reload
    npm --prefix frontend run dev
