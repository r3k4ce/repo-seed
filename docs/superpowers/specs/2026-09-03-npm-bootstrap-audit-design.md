# npm Bootstrap Audit Opt-Out

## Problem, Goal, and User-Visible Outcome

When the web or game scaffolder installs frontend dependencies, npm 11 starts
an advisory-service request after resolving and installing the packages. On the
reported Windows environment that request can wait for npm's five-minute
network timeout. The only visible output during the wait is an unrelated
deprecation warning for ESLint 9, which makes the scaffolder appear stuck.

The goal is for the initial frontend installation performed by RepoSeed to
finish without waiting for npm's optional audit request. A new web or game
project should continue to the remaining scaffold steps after dependencies are
installed, while dependency selection, lockfile creation, package lifecycle
scripts, and the existing ESLint warning remain unchanged.

## Scope and Non-goals

### In scope

- Pass `--no-audit` to the initial frontend `npm install` in
  `new-project.ps1` for the `web` and `game` profiles.
- Pass `--no-audit` to the matching initial frontend `npm install` in
  `new-project.sh`.
- Extend the existing fast contract tests so fake npm commands record and
  verify the actual arguments received by both scaffolders.
- Keep the Git Bash cross-platform contract from attempting its PowerShell
  subsection in a MINGW or MSYS environment, where the existing fake `uv`
  command does not provide a reliable PowerShell exit-code signal.

### Non-goals

- Do not change dependency versions or remove the ESLint 9 deprecation warning.
- Do not change generated `npm ci` commands in GitHub Actions.
- Do not change the generated README's later manual `npm install` command.
- Do not change user-wide npm configuration, npm retry settings, or npm timeout
  settings.
- Do not change the `npm exec playwright install chromium` step for the game
  profile.
- Do not change base or desktop profiles, existing projects, installers, or
  frontend templates.
- Do not add a dependency, shared abstraction, or new test framework.

## Current Behavior and Repository Constraints

The repository has two independent scaffolders:

- `new-project.ps1` resolves Windows-safe `npm.cmd` when available and calls
  `Invoke-Checked $NpmCommand install` inside the shared `web`/`game` branch
  at the current line 596.
- `new-project.sh` calls `invoke_checked npm install` inside the shared web/game
  creation path at the current line 1150.

Both checked-command helpers already forward additional arguments and exit with
the child command's nonzero status. No error-handling change is needed.

The observed npm 11.11.0 log shows dependency installation and
`esbuild@0.28.2`'s postinstall completing, then stops before npm prints its
normal exit record. npm's installed registry-fetch implementation uses a
five-minute timeout, and npm's Arborist waits for the audit promise before
returning from `npm install`. This supports the audit request as the root cause
of the apparent wait; the ESLint message is only a warning.

The installed Windows command is a wrapper at
`%LOCALAPPDATA%\Microsoft\WindowsApps\reposeed.ps1` that runs the managed copy
at `%LOCALAPPDATA%\RepoSeed\new-project.ps1`. That managed copy is older than
the current checkout and still contains removed `AGENTS.md` generation. The
repository's existing installer already refreshes this managed copy when
`install.ps1` is run again. No installer implementation change is required;
the user must rerun `install.ps1` after the repository fix before using the
installed command.

## Chosen Design

Pass the npm option directly at the existing bootstrap call sites:

```powershell
Invoke-Checked $NpmCommand install --no-audit
```

```bash
invoke_checked npm install --no-audit
```

This keeps the behavior local to RepoSeed's initial install, is visible to
readers of the generator, and uses npm's native option. A global npm setting
was rejected because it would silently affect unrelated projects and shells.
Adding a custom timeout or retry loop was rejected because it would preserve
the advisory-service dependency rather than removing the wait that blocks
scaffolding. Updating ESLint was rejected because the warning is unrelated to
the wait and would change dependency compatibility without solving the network
problem.

## Components, Interfaces, and Data Flow

The existing flow remains direct:

1. The user selects `web` or `game`.
2. The generator writes the frontend `package.json` and source files.
3. The generator invokes the existing npm command with `install --no-audit`.
4. npm resolves the same dependency ranges, writes the same lockfile, runs the
   same package lifecycle scripts, and skips only its advisory request.
5. The generator writes the remaining project files. For `game`, it then runs
   the existing `npm exec playwright install chromium` command.

The exact interface between the generator and npm is the argument list
`install --no-audit`. The existing `npm.cmd` selection on Windows and
`invoke_checked`/`Invoke-Checked` failure propagation remain the interfaces for
command lookup and error handling.

The fast tests use a temporary fake npm command. Each invocation writes its
received argument string as one line to a temporary log. The expected records
are:

- Web: one line, `install --no-audit`.
- Game: first line `install --no-audit`, second line
  `exec playwright install chromium`.

## Functional Behavior

### Web profile

- PowerShell and Bash pass `install --no-audit` for the initial frontend
  dependency installation.
- The generator continues writing the README, scripts, CI files, hooks, and
  memory file after npm returns.
- The dependency ranges, lockfile contents, lifecycle behavior, and existing
  warning output are otherwise unchanged.

### Game profile

- PowerShell and Bash pass `install --no-audit` for the initial frontend
  dependency installation.
- The existing Playwright Chromium installation command runs after the initial
  install with its current arguments.
- No optional frontend test behavior or game-specific generated files change.

### Other profiles and later commands

- Base and desktop profiles do not invoke npm and remain unchanged.
- Generated CI continues to use its existing `npm ci` commands.
- Generated README setup text continues to show its existing later manual
  `npm install` command.
- Users can run `npm audit` separately whenever they want the advisory report.

## Error Handling and Boundary Conditions

- Missing npm remains the existing error before the web/game frontend install.
- If npm exits nonzero, the existing checked-command helper exits with that
  status; the generator does not continue or hide the failure.
- If the game Playwright command exits nonzero, the existing checked-command
  behavior remains in force.
- An npm audit service outage no longer blocks the initial install because that
  request is not made.
- A local npm configuration that already disables audit produces the same
  result as before this change.
- The option is passed as a separate argument, so it remains safe for the
  Windows `npm.cmd` invocation and the Bash `npm` invocation.

## Compatibility, Migration, and Platform Constraints

- No public RepoSeed option, generated dependency range, persisted project
  data, or package-lock format changes.
- Existing generated projects are not modified.
- GitHub Actions behavior remains unchanged, including its existing npm audit
  behavior through `npm ci`.
- The change works with npm versions that support the existing `--no-audit`
  option and requires no new dependency.
- Windows users who invoke the installed `reposeed` command must rerun
  `install.ps1` from this checkout to copy the fix into `%LOCALAPPDATA%\RepoSeed`.

## Acceptance Criteria

### Scenario: PowerShell web bootstrap skips the npm audit request

Given a fresh directory and fake `uv` and `npm.cmd` commands that record npm
arguments
When `new-project.ps1 -Profile web -NoGit -NoInstallHooks` runs
Then the recorded npm calls contain exactly one line, `install --no-audit`
And the generator writes files after the install call, including
`scripts/check.ps1` and `README.md`

### Scenario: Bash web bootstrap skips the npm audit request

Given a fresh directory and fake `uv` and `npm` commands that record npm
arguments
When `new-project.sh --profile web --no-git --no-install-hooks` runs
Then the recorded npm calls contain exactly one line, `install --no-audit`
And the generator writes files after the install call, including
`scripts/check.sh` and `README.md`

### Scenario: Game bootstrap skips audit and preserves Playwright setup

Given a fresh game project and a fake npm command that records arguments
When either scaffolder creates the game project
Then its first npm call is `install --no-audit`
And its next npm call remains `exec playwright install chromium`

### Scenario: npm failures still stop scaffolding

Given the initial frontend npm command exits with a nonzero status
When either web or game scaffolding reaches that command
Then the scaffolder exits with the same nonzero status
And it does not claim that project creation completed

### Scenario: CI installation behavior is preserved

Given a generated web or game GitHub Actions workflow
When its frontend dependency-install step is read
Then it still contains the existing `npm ci` command
And no bootstrap `--no-audit` option is inserted into CI

### Scenario: Non-web profiles are preserved

Given a base or desktop profile
When the profile is scaffolded
Then no npm install command is introduced
And its existing generated files and checks remain unchanged

## Testing Strategy

- `tests/powershell_web_contract.ps1` uses fake Windows commands, records the
  web and game npm arguments, and asserts the exact call sequences plus the
  existing web generated-artifact contract.
- `tests/cross_platform_contract.sh` uses fake Bash commands, records the web
  and game npm arguments, and asserts the exact call sequences. Its existing
  PowerShell subsection skips only under MINGW/MSYS because native PowerShell
  coverage is provided by the dedicated PowerShell contract test.
- `tests/scaffold_e2e.ps1` runs the real PowerShell web scaffold and generated
  checks, providing integration evidence that the real install returns and the
  remaining files exist.
- `tests/scaffold_e2e.sh` runs the real Bash base and web scaffolds; its
  existing `REPOSEED_E2E_GAME=1` option remains available for game coverage.
- `git diff --check`, Bash syntax parsing, PowerShell syntax parsing, and the
  existing command-help check cover script cleanliness and invocation shape.

## Mechanical Assumptions and Deferred Work

- The repository's existing fake-command tests are sufficient; no test
  framework or reusable command abstraction is needed.
- The current npm option spelling is stable for the supported Node.js/npm
  requirement.
- A later manual `npm install` may still contact the advisory service because
  that generated README command is explicitly outside this change. Users who
  need that install to avoid the request can add `--no-audit` themselves.
- Improving npm progress output, changing registry timeouts, upgrading ESLint,
  and changing CI audit policy are deferred because they are separate behavior
  decisions.
