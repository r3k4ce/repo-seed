# PowerShell Web Profile Parity

## Problem and goal

`new-project.ps1 -Profile web` currently creates a different React frontend
than `new-project.sh --profile web`. The Windows result lacks the Bash
profile's pinned dependencies, Tailwind integration, frontend coverage, and
required type-check step. Its generated CI also treats the web project like a
game project by conditionally running Playwright commands.

Make the PowerShell web profile generate the same web frontend tooling and
quality checks as the Bash web profile. Shell-specific generated files remain
PowerShell files on Windows.

## Scope

In scope:

- The PowerShell web `package.json`, Vite configuration, check script, fix
  script, and GitHub Actions workflow.
- A fast native PowerShell web scaffold contract test.
- A full PowerShell web scaffold e2e test that installs dependencies and runs
  the generated PowerShell check script when `pwsh` is available.

Out of scope:

- Changes to the Bash scaffolder's generated output.
- Changes to the `base`, `desktop`, or `game` profiles.
- Moving duplicated generator strings into shared templates.
- Adding Tailwind classes or changing the existing shared React/CSS starter.

## Current constraints

- `new-project.ps1` supports `base`, `desktop`, `web`, and `game`.
- Its web and game profiles currently share generated PowerShell check/fix/CI
  content.
- `new-project.sh` already defines the desired web frontend output and is the
  source of truth for parity.
- Shared files in `templates/web/` are plain React/CSS and do not require a
  starter Tailwind import or utility classes.
- The repository's Bash tests already assert the Bash web contract; the
  PowerShell test currently covers only the base scaffold.

## Chosen design

Keep the two generators independent and make the PowerShell web branch mirror
the existing Bash web branch's generated artifacts.

### Generated frontend

For `-Profile web`, PowerShell writes a `frontend/package.json` with:

- `react` and `react-dom` as runtime dependencies at the same pinned version
  ranges as Bash.
- Vite, TypeScript, React plugin/types, ESLint packages, Vitest, jsdom,
  Testing Library, `@vitest/coverage-v8`, `tailwindcss`, and
  `@tailwindcss/vite` as the same pinned development dependencies as Bash.
- `test` set to `vitest run --coverage` and `test:watch` set to `vitest`.
- No Playwright dependency or `test:e2e` script.

Its Vite configuration imports and enables the React and Tailwind plugins and
configures Vitest's v8 coverage provider. Coverage reports text, JSON, and
HTML; statements, branches, functions, and lines must each meet 80%. The
configuration excludes the entrypoint, Vite declaration, test setup, and test
files, matching Bash exactly.

### Generated checks and CI

For the web profile only, generated `scripts/check.ps1` and `scripts/fix.ps1`
run backend format/lint/type/test checks, then frontend commands in this exact
order:

1. `npm run test`
2. `npm run typecheck`
3. `npm run lint`
4. `npm run build`

These commands are required, not optional. They do not run `test:e2e`.

The generated web GitHub Actions workflow follows the same frontend sequence
after backend checks. It has no Playwright installation step. The game profile
continues using its current browser-test workflow and optional frontend test
commands.

### Tests

Add `tests/powershell_web_contract.ps1` to scaffold a PowerShell web project
with fake `uv` and `npm` commands, then assert its generated frontend files,
PowerShell scripts, pre-push hook, and CI contain the parity contract. A native
PowerShell test avoids relying on a Bash environment to invoke Windows
PowerShell.

Add `tests/scaffold_e2e.ps1` as a native Windows web e2e test. It scaffolds a
fresh web project with real `uv` and `npm`, runs `scripts/check.ps1`,
`scripts/fix.ps1`, and `scripts/check.ps1` again through PowerShell, and
applies the same web artifact assertions as the Bash case. A native PowerShell
test avoids relying on a Bash environment to invoke Windows PowerShell.

## Error and boundary behavior

- Missing `uv` or `npm` remains an existing scaffolder error before a project
  is created.
- The native PowerShell contract and e2e are run only where PowerShell is
  available; the e2e also requires uv and npm.
- A generated web project fails its check when frontend coverage, tests, type
  checking, linting, or build fails.
- The game profile continues to permit absent optional frontend test scripts
  and install Playwright Chromium.

## Compatibility

No persisted project data or public command-line options change. New projects
created with PowerShell's web profile gain the same dependency versions and
quality gates already used by newly created Bash web projects. Existing
projects are not modified.

## Acceptance criteria

### PowerShell web frontend tooling

Given an empty project directory
when `new-project.ps1 -Profile web` runs
then `frontend/package.json` contains the Bash web profile's pinned React,
Tailwind, Vitest coverage, and lint/type dependencies, `vitest run --coverage`,
and `test:watch`, and contains neither `"latest"` nor Playwright entries.

Given a PowerShell-scaffolded web project
when its Vite configuration is read
then it enables the React and Tailwind plugins and configures v8 coverage with
80% thresholds and the same excludes as Bash.

### PowerShell web quality gates

Given a PowerShell-scaffolded web project
when `scripts/check.ps1` or `scripts/fix.ps1` reaches the frontend
then it requires test, typecheck, lint, and build in that order and does not
invoke browser tests.

Given a PowerShell-scaffolded web project with GitHub Actions enabled
when CI runs
then it runs frontend test, typecheck, lint, and build without a
Playwright install step.

### Verification coverage

Given PowerShell is available
when `tests/powershell_web_contract.ps1` runs
then it validates the PowerShell web generated-artifact contract.

Given PowerShell, uv, and npm are available
when `tests/scaffold_e2e.ps1` runs
then it creates a PowerShell web project and its generated format, lint, type,
test, coverage, and build checks pass before and after the generated fix script.

## Testing strategy

- `tests/powershell_web_contract.ps1`: fast generated-file contract for the
  PowerShell web route, using fake `uv` and `npm` commands.
- `tests/scaffold_e2e.sh`: existing full Bash e2e coverage.
- `tests/scaffold_e2e.ps1`: full native PowerShell web e2e coverage.
- Run the PowerShell e2e with `pwsh -NoProfile -File`; it runs the generated
  `.ps1` scripts.

## Mechanical assumptions

- The tested machine provides `pwsh`, `uv`, and `npm`; missing `pwsh` is an
  intentional skip condition for PowerShell-specific tests.
- PowerShell's `npm.cmd` preference remains the generated script's existing
  Windows-safe command resolution.
