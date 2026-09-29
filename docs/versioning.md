# Version policy

RepoSeed's job is to produce the same working project every time you run it.
The only way a scaffolder can promise that is to decide every version itself
instead of asking a package registry what "latest" means today.

## The rules

1. **Every dependency RepoSeed installs is pinned to one exact version** in
   [`versions.env`](../versions.env). Python packages are added with
   `uv add name==version`; npm packages are written into `package.json`
   without `^` or `~`. Both scaffolders read the same file, so there is no
   second copy of any version number to fall out of sync.
2. **A pinned set is only accepted once it passed the tests.** The tests in
   `tests/` scaffold real projects and run their generated `check`/`fix`
   scripts. A version bump that breaks the generated project cannot be
   merged.
3. **Tools on your machine are checked, not assumed.** `versions.env` also
   holds the minimum `uv` and Node.js versions. The scaffolders refuse to
   run with older tools and tell you what to update, instead of failing
   halfway through with a confusing error.
4. **The generated project stays reproducible after you start working.**
   `uv.lock` and `package-lock.json` are created at scaffold time, the
   generated CI runs `uv sync --locked` and `npm ci`, and `frontend/.npmrc`
   sets `save-exact=true` so later `npm install <pkg>` calls pin too.
5. **CI re-scaffolds weekly.** The workflow in `.github/workflows/ci.yml`
   runs on every push and on a weekly schedule, so a yanked package or a
   registry-side change shows up as a red build before it costs you a
   project start.

## Why exact pins and not ranges

The scaffolder used to write ranges like `"vite": "^7.0.0"` and even
`"typescript": "latest"`. Ranges let a registry pick a different version on
every run, which means the project you scaffold next month is not the one
that was tested. Two real breakages seen while writing this policy:

- `"typescript": "latest"` resolved to TypeScript 7, which
  `typescript-eslint` does not support, so `npm run lint` failed on a fresh
  project.
- The caret ranges triggered a crash inside npm 10's dependency resolver
  (`Cannot read properties of null (reading 'edgesOut')`) on `npm install`,
  so the scaffold never finished. The same packages with exact versions
  install fine on the same npm.

Exact pins make a fresh project slightly older than "latest". That is the
trade: you upgrade on your schedule, in a project that already has passing
checks, instead of debugging someone else's release on day one.

## How to bump versions

1. Edit `versions.env`. Keep peer requirements in mind: `vitest` and
   `@vitest/coverage-v8` must be the same version, `@vitejs/plugin-react`
   has a `vite` major it supports, and `typescript-eslint` sets the highest
   TypeScript it accepts. `npm view <pkg> peerDependencies` shows these.
2. Run the tests:

   ```bash
   bash tests/cross_platform_contract.sh
   REPOSEED_E2E_GAME=1 bash tests/scaffold_e2e.sh
   ```

   On Windows:

   ```powershell
   pwsh -NoProfile -File tests/powershell_web_contract.ps1
   pwsh -NoProfile -File tests/scaffold_e2e.ps1
   ```

3. Commit `versions.env` with a short note in `CHANGELOG.md`.

Bumping the minimum tool versions (`UV_MIN`, `NODE_MIN`) follows the same
steps. Raise `NODE_MIN` whenever a pinned npm package's `engines.node`
requires it.

## Upgrading inside a generated project

Generated projects are independent of RepoSeed after scaffolding. To upgrade
a dependency there, change its version in `pyproject.toml` or
`frontend/package.json`, then run `uv lock` or `npm install`, and run the
checks (`./scripts/check.sh` or `.\scripts\check.ps1`).
