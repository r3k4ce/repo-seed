# Vitest npm Peer-Resolution Stability

## Problem, Goal, and User-Visible Outcome

The RepoSeed `web` profile currently writes Vitest dependency ranges that can
resolve to a Vitest release whose optional peer-dependency graph crashes npm
10's dependency resolver. On the affected Windows setup, the backend is
created successfully, but the frontend install stops with:

```text
Cannot read properties of null (reading 'edgesOut')
```

The goal is for a fresh `web` project to finish its frontend installation on
the npm 10 toolchain already supported by RepoSeed. The generated project must
keep its current React, Vite, Tailwind, test, lint, type-check, build, CI, and
backend behavior.

## Scope and Non-goals

### In scope

- Change the generated web `vitest` and `@vitest/coverage-v8` entries in both
  scaffolders from the drifting `^4.1.9` range to the aligned exact version
  `4.1.10`.
- Update the existing PowerShell and Bash web contract/e2e assertions to prove
  both exact versions are generated.
- Preserve the existing `npm install --no-audit` bootstrap behavior.
- Verify the real PowerShell web scaffold completes with the affected npm 10
  installation and runs its generated checks.
- Verify that rerunning the Windows installer copies the corrected scaffolder
  into the managed RepoSeed directory.

### Non-goals

- Do not add `--force`, a global `.npmrc` setting, or an
  npm timeout/retry workaround.
- Do not upgrade or select a different Node.js/npm installation in the
  scaffolder.
- Do not change generated README setup commands, CI `npm ci`, or lifecycle
  scripts in this cycle; if they hit the same npm 10 resolver crash, that is
  separately verified follow-up work.
- Do not change React, Vite, Tailwind, TypeScript, ESLint, or other dependency
  ranges.
- Do not change generated README setup commands, GitHub Actions `npm ci`,
  package lifecycle scripts, or lockfile behavior.
- Do not change the game, base, desktop, or existing-project paths.
- Do not modify `install.ps1` implementation; users refresh its managed copy by
  rerunning the existing installer after updating RepoSeed.
- Do not update historical Superpowers reports or older design/plan documents.

## Current Behavior and Repository Constraints

The repository has independent Bash and PowerShell scaffolders. Their web
branches currently generate these entries in `frontend/package.json`:

```json
"@vitest/coverage-v8": "^4.1.9",
"vitest": "^4.1.9"
```

The caret ranges allow a fresh install to resolve a newer release than the
one that was verified when the generator was written. The reported npm log
shows Node `v22.23.2`, npm `10.9.8`, and a root `npm install` invocation. It
ends in npm Arborist's `#loadPeerSet` method at the `node.parent.edgesOut`
access while the unfinished ideal tree is processing `node_modules/vitest`.

The current checkout already passes `--no-audit` to the initial web/game
install at `new-project.ps1:596` and `new-project.sh:1150`. The user's
installed `reposeed.ps1` is a wrapper for the older managed copy at
`%LOCALAPPDATA%\RepoSeed\new-project.ps1`; that copy still runs plain
`npm install`. The existing `install.ps1` replaces the managed copy when it is
run again, so no installer code change is needed.

The exact version choice is based on the observed npm/Vitest compatibility
boundary: npm issue reports reproduce this null peer-tree crash with Vitest
4.1.9 and report successful npm 10 resolution with Vitest 4.1.10. The exact
pair is aligned because `@vitest/coverage-v8@4.1.10` declares `vitest` as an
exact peer at `4.1.10`.

Relevant references:

- npm CLI documentation: `--no-audit` disables the advisory request but does
  not alter dependency resolution.
- npm CLI issue #9787 and its Vitest reproduction comments document the
  `edgesOut` crash and the version boundary.

## Chosen Design

Keep both scaffolders independent and change only their generated web package
metadata:

```json
"@vitest/coverage-v8": "4.1.10",
"vitest": "4.1.10"
```

The initial install becomes:

```text
npm install --no-audit --legacy-peer-deps
```

The exact pin alone proved insufficient: a bare `vitest@4.1.10` package
crashes npm 10.9.8 with the same `edgesOut` null-parent failure in Arborist's
`#loadPeerSet` (observed peer chain: `vitest@*` through
`@vitest/browser-playwright` into `jsdom`/`canvas`), while the same package
installs cleanly with `--legacy-peer-deps`. The crash is in the resolver
itself, before any peer-conflict validation could run, so the flag bypasses
only the crashed loader step rather than hiding a real version conflict. The
exact pin is kept so generated projects still resolve a single known Vitest
release instead of drifting.

`--force` is rejected because it overrides more safety checks than needed.
Selecting npm 11 is rejected because it makes the result depend on the
machine's PATH and does not guarantee that every future peer graph is safe.
Keeping `^4.1.9` is rejected because a new project can silently select a
different Vitest graph without any RepoSeed source change.

## Components, Responsibilities, and Data Flow

1. The user runs the Bash or PowerShell web scaffolder.
2. The selected generator writes a frontend package containing exact Vitest
   and coverage-provider version `4.1.10`.
3. The generator invokes the existing npm command with `install --no-audit --legacy-peer-deps`.
4. npm resolves the stable, aligned Vitest peer contract and returns control to
   the generator instead of crashing during `idealTree` construction.
5. The generator writes the remaining project files and reports the existing
   completion message.
6. The generated test, type-check, lint, build, backend, and CI paths continue
   to operate as before.

The generated package JSON is the only new interface. Its exact required
values are:

```text
"@vitest/coverage-v8": "4.1.10"
"vitest": "4.1.10"
```

The npm argument interface is `install --no-audit --legacy-peer-deps` for web and
game bootstrap installs (one shared call per generator). The existing game follow-up remains
`exec playwright install chromium`.

## Functional Behavior

### Web profile

- Bash and PowerShell generate exact Vitest version `4.1.10` for both Vitest
  and its v8 coverage provider.
- The initial frontend install passes `--no-audit --legacy-peer-deps`.
- A real fresh web scaffold completes on the affected npm 10 environment.
- The generated frontend still runs `vitest run --coverage`, typecheck, lint,
  and build in the existing order.

### Game profile

- The game package remains unchanged and does not gain Vitest dependencies.
- The initial game install still shares the web bootstrap call, now `install --no-audit --legacy-peer-deps`.
- The next npm call remains `exec playwright install chromium`.

### Other profiles and existing projects

- Base and desktop profiles do not invoke npm and remain unchanged.
- Existing generated projects are not rewritten.
- GitHub Actions continues to use its existing `npm ci` command.
- The generated README continues to show its existing manual `npm install`.

## Error Handling and Boundary Conditions

- Missing npm remains the existing pre-install error.
- A nonzero npm exit still stops scaffolding through the existing checked
  command helper.
- If the stable exact Vitest pair cannot be installed, the real e2e must fail;
  the implementation must not hide the failure with peer-dependency bypasses.
- The exact version is a deliberate stability pin. Future Vitest updates are
  separate dependency-update work and must be verified against the supported
  npm versions before changing this generator.
- Rerunning `install.ps1` refreshes only the managed RepoSeed payload and does
  not alter old projects or global npm configuration.

## Compatibility, Migration, and Platform Constraints

- No public RepoSeed option changes.
- No new dependency is added.
- The generated frontend remains compatible with the existing Node/npm
  requirement and the current Vite/React stack.
- Existing users of the installed Windows command must rerun
  `install.ps1` from the updated checkout; changing the repository alone does
  not update `%LOCALAPPDATA%\RepoSeed`.
- The repository remains cross-platform: Bash and PowerShell receive the same
  package values, with shell-specific file generation unchanged.

## Acceptance Criteria

### Scenario: PowerShell web generation pins the compatible Vitest pair

Given a fresh directory and the fake commands used by the PowerShell contract
When `new-project.ps1 -Profile web -NoGit -NoInstallHooks` runs
Then `frontend/package.json` contains
`"@vitest/coverage-v8": "4.1.10"`
And it contains `"vitest": "4.1.10"`
And it does not contain either old `^4.1.9` Vitest range
And the npm call is exactly `install --no-audit --legacy-peer-deps`

### Scenario: Bash web generation pins the compatible Vitest pair

Given a fresh directory and the fake commands used by the Bash contract
When `new-project.sh --profile web --no-git --no-install-hooks --no-github-actions` runs
Then `frontend/package.json` contains the same two exact `4.1.10` entries
And the npm call is exactly `install --no-audit --legacy-peer-deps`
And generation writes `README.md` after the install call

### Scenario: Real PowerShell web bootstrap completes with npm 10

Given PowerShell, uv, npm 10.9.8, and a fresh directory
When `tests/scaffold_e2e.ps1` creates the web project
Then npm completes without the `edgesOut` exception
And the generator writes the generated check scripts
And the backend and frontend check, fix, and final check sequence exits 0

### Scenario: Game bootstrap behavior is preserved

Given a fresh game directory and the existing fake commands
When either scaffolder creates the game project
Then the first npm call is `install --no-audit --legacy-peer-deps`
And the next npm call is `exec playwright install chromium`
And the game package has no Vitest entries introduced by this change

### Scenario: CI and manual setup behavior are preserved

Given generated web and game projects
When their workflow and README are inspected
Then the workflow still uses `npm ci`
And the README still uses its existing manual `npm install`
And neither contains a new global audit or peer-dependency setting

### Scenario: The installed Windows command receives the fix

Given the updated checkout and an isolated installer destination
When the existing `install.ps1` runs with temporary bin and data directories
Then the managed `new-project.ps1` contains the exact `4.1.10` pair
And it contains the `install --no-audit --legacy-peer-deps` bootstrap call
And its wrapper points to that managed script

### Scenario: Non-web profiles remain unchanged

Given a base or desktop profile
When it is scaffolded
Then it does not introduce npm or Vitest dependencies
And its existing generated files and checks remain unchanged

## Testing Strategy

- `tests/powershell_web_contract.ps1` remains the fast native Windows
  contract. It asserts both exact package entries, the existing generated web
  artifact contract, the absence of Vitest entries from the game package, and
  the web/game npm argument sequences.
- `tests/cross_platform_contract.sh` remains the fast Bash contract. Its fake
  npm path asserts the exact web package entries, the absence of Vitest entries
  from the game package, and existing web/game command sequences; its Git Bash
  PowerShell subsection behavior remains unchanged.
- `tests/scaffold_e2e.ps1` performs the real Windows dependency install and
  generated `check -> fix -> check` sequence. It is the direct regression for
  the reported npm 10 crash.
- `tests/scaffold_e2e.sh` performs the existing real Bash web regression and
  reasserts the exact package entries.
- PowerShell parsing, Bash syntax checks, command help, installer-copy
  verification, `git diff --check`, and the existing scope search cover script
  integrity and excluded behavior.

The focused contract assertions are written first and must fail against the
current `^4.1.9` output. Production generator changes are then made, followed
by the real e2e checks and final verification.

## Mechanical Assumptions and Deferred Work

- The supported npm 10 environment is the compatibility floor for this fix;
  no npm upgrade is required.
- Exact `4.1.10` is the smallest known-good Vitest release for the observed
  npm 10 peer-resolution failure and will be confirmed by the real e2e before
  completion.
- The generated lockfile is intentionally not committed to RepoSeed; exact
  top-level Vitest pins are the generator's stability boundary.
- Refreshing the user's installed command is an operational step after the
  repository change, not a change to installer behavior.
- Future Vitest upgrades, npm resolver upgrades, and broader dependency
  refreshes are deferred until separately verified.
