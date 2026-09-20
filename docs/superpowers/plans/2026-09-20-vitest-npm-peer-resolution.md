# Vitest npm Peer-Resolution Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make fresh RepoSeed web projects install the supported Vitest toolchain successfully with npm 10 instead of crashing in npm Arborist's peer resolver.

**Architecture:** Keep the Bash and PowerShell scaffolders independent. Replace only the two web Vitest caret ranges with the aligned exact `4.1.10` pair, pass `--legacy-peer-deps` on the single shared web/game bootstrap install call alongside the existing `--no-audit`, and extend the existing contract/e2e assertions. Do not add a shared abstraction.

**Tech Stack:** PowerShell 7, Bash/Git Bash, npm 10.9.8, Node.js 22, uv, React 19, Vite 7, Vitest 4.1.10, existing contract and scaffold e2e scripts.

## Global Constraints

- Generated web `@vitest/coverage-v8` must be exactly `4.1.10`.
- Generated web `vitest` must be exactly `4.1.10`.
- Generated web `@testing-library/dom` must be exactly `^10.0.0` (explicit peer of `@testing-library/react@16` that legacy resolution no longer auto-installs).
- Initial web/game frontend installation must be `npm install --no-audit --legacy-peer-deps` or the PowerShell equivalent using `$NpmCommand` (one shared call per generator; `--legacy-peer-deps` bypasses npm 10's crashed `#loadPeerSet` peer loader, verified against bare `vitest@4.1.10`).
- Do not add `--force`, an `.npmrc` setting, an npm upgrade, or an npm retry/timeout workaround.
- Do not change React, Vite, Tailwind, TypeScript, ESLint, or other dependency ranges, except the `@testing-library/dom` `^10.0.0` addition above.
- Do not change generated README `npm install`, CI `npm ci`, lifecycle scripts, lockfile behavior, Playwright installation, or non-web profiles.
- Keep existing checked-command helpers and nonzero exit propagation unchanged.
- Keep the Bash and PowerShell generators independent; do not introduce a dependency or shared package-generation helper.
- Existing generated projects are not modified.
- Historical design, plan, task-report, and ledger files are not edited.
- Current repository context: branch `main`, HEAD `5a706eb555ccc26f540e617e97bdf1ebf4dc59a4`.
- Pre-existing unrelated worktree noise remains untouched: modified `.superpowers/sdd/progress.md` and untracked cycle1 hardening spec/plan documents.

---

## Baseline Evidence

The fresh baseline was rechecked before this plan was written:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1` -> exit 0, `PowerShell web contract passed`.
- `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` -> exit 0, Git Bash skips only the PowerShell subsection, `cross-platform contract tests passed`.
- Git Bash syntax checks for `new-project.sh` and `tests/cross_platform_contract.sh` -> exit 0.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File new-project.ps1 -?` -> exit 0, usage shown.
- `git diff --check` -> exit 0; it reports only the existing CRLF warning for untouched `.superpowers/sdd/progress.md`.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1` -> expected pre-fix failure: the real npm 10.9.8 install stops with `Cannot read properties of null (reading 'edgesOut')` while resolving Vitest, before generated check scripts exist.

The current source generates `^4.1.9` at `new-project.ps1:358,368` and
`new-project.sh:683,693`. The current installed managed copy is stale, but the
source fix is still required because the caret ranges can resolve the same
problematic peer graph after the installer is refreshed.

## File Map

| File | Action | Responsibility |
| --- | --- | --- |
| `new-project.ps1` | Modify | Generate exact web Vitest and coverage-provider version `4.1.10`. |
| `new-project.sh` | Modify | Generate the same exact web Vitest pair as PowerShell. |
| `tests/powershell_web_contract.ps1` | Modify | Assert both exact web package entries, game-package absence, and existing npm-call/artifact behavior. |
| `tests/cross_platform_contract.sh` | Modify | Assert exact Bash web package entries, game-package absence, and existing fake npm call behavior. |
| `tests/scaffold_e2e.ps1` | Modify | Assert exact package entries in the real Windows web e2e. |
| `tests/scaffold_e2e.sh` | Modify | Assert exact package entries in the real Bash web e2e. |
| `docs/superpowers/specs/2026-09-20-vitest-npm-peer-resolution-design.md` | Create | Binding behavior, boundaries, acceptance scenarios, and testing strategy. |
| `docs/superpowers/plans/2026-09-20-vitest-npm-peer-resolution.md` | Create | This task-by-task implementation and verification plan. |

No installer implementation, README, CHANGELOG, frontend template, CI file,
game package, or new test file is modified.

## Acceptance-to-Test Map

| Acceptance behavior | Concrete proof |
| --- | --- |
| PowerShell web package uses exact `4.1.10` pair | `tests/powershell_web_contract.ps1` asserts both literal package lines after the fake install. |
| Bash web package uses exact `4.1.10` pair | `tests/cross_platform_contract.sh` asserts both literal package lines after the fake install. |
| npm 10 real web bootstrap no longer crashes | `tests/scaffold_e2e.ps1` completes the real install and generated check/fix/check sequence with exit 0. |
| Bash real web bootstrap remains healthy | `tests/scaffold_e2e.sh` completes its existing web check/fix/check sequence with exit 0. |
| Web/game npm calls use the bypass and game stays Vitest-free | Fake npm log assertions expect `install --no-audit --legacy-peer-deps` (Task 2) plus literal game-package absence assertions in `tests/powershell_web_contract.ps1` and `tests/cross_platform_contract.sh`. |
| Explicit dom peer declared | All four web contract/e2e tests assert `"@testing-library/dom": "^10.0.0"` (Task 3); both real e2es prove the generated vitest run finds it. |
| CI and README behavior stays unchanged | Final scope search confirms only the two package lines changed; existing generated CI/artifact assertions remain in the contracts/e2e tests. |
| Installer copies the corrected source | Isolated `install.ps1` verification reads the managed payload and wrapper target. |
| Non-web profiles stay unchanged | Production diff scope plus existing base contract; no non-web generation lines are touched. |

## Implementation Task

### Task 1: Pin the Web Vitest Peer Contract

**Task Position**

- **Feature goal:** Fresh web scaffolds complete frontend installation on npm 10 without the Vitest peer-resolution crash.
- **Previously:** The verified baseline is `main` at `5a706eb555ccc26f540e617e97bdf1ebf4dc59a4`; fast Bash and PowerShell contracts pass, while the real PowerShell web e2e reproduces npm's `edgesOut` crash. The generators use `^4.1.9` for both Vitest entries and already pass `--no-audit`.
- **Current:** Make both generators emit exact aligned `4.1.10` Vitest entries, prove the exact package output in all existing web contracts/e2e tests, and verify real npm 10 installation plus the refreshed managed installer payload.
- **Next:** Final whole-branch review will inspect the complete diff against the approved spec and rerun the final verification set.
- **Do not do yet:** Do not change npm selection, peer-dependency flags, installer implementation, CI/README commands, package ranges other than the two Vitest entries, game behavior, non-web profiles, or historical artifacts.

**Files:**

- Modify: `new-project.ps1:340-370`, the non-game web `frontend/package.json` here-string.
- Modify: `new-project.sh:657-695`, the non-game web `frontend/package.json` string.
- Modify: `tests/powershell_web_contract.ps1:123-131`, existing web package assertions.
- Modify: `tests/cross_platform_contract.sh:220-229`, Bash fake-install web package assertions.
- Modify: `tests/scaffold_e2e.ps1:93-101`, existing real PowerShell web package assertions.
- Modify: `tests/scaffold_e2e.sh:59-75`, existing real Bash web package assertions.

**Interfaces:**

- Consumes: Existing `new-project.ps1 -Profile web`, `new-project.sh --profile web`, fake `uv`/`npm` commands, and real npm/uv e2e tools.
- Produces: Generated web package lines exactly `"@vitest/coverage-v8": "4.1.10"` and `"vitest": "4.1.10"`.
- Preserves: Initial npm argument sequence `install --no-audit --legacy-peer-deps`; game sequence `install --no-audit --legacy-peer-deps` then `exec playwright install chromium`; all existing generated check, CI, README, and backend interfaces.

- [ ] **Step 1: Add the failing exact-version assertions before production changes**

Update the four existing web contract/e2e tests so they require the approved
exact pair. Do not add a new test file or alter their temporary command setup.

In `tests/powershell_web_contract.ps1`, replace the current coverage assertion
and add the matching Vitest assertion:

```powershell
Assert-Contains -Path $PackageJson -Expected '"@vitest/coverage-v8": "4.1.10"'
Assert-Contains -Path $PackageJson -Expected '"vitest": "4.1.10"'
Assert-NotContains -Path $PackageJson -Unexpected '"@vitest/coverage-v8": "^4.1.9"'
Assert-NotContains -Path $PackageJson -Unexpected '"vitest": "^4.1.9"'
```

In `tests/cross_platform_contract.sh`, immediately after the existing
`README.md` existence assertion in `run_bash_web_and_game_install_contract`,
add:

```bash
assert_file_contains "$project_dir/frontend/package.json" '"@vitest/coverage-v8": "4.1.10"'
assert_file_contains "$project_dir/frontend/package.json" '"vitest": "4.1.10"'
```

After the game scaffold returns and its npm call sequence is asserted, add:

```bash
assert_file_not_contains "$game_dir/frontend/package.json" '"vitest"'
assert_file_not_contains "$game_dir/frontend/package.json" '"@vitest/coverage-v8"'
```

In `tests/powershell_web_contract.ps1`, after the existing game npm call
sequence assertion, add:

```powershell
$GamePackageJson = Join-Path $GameDir "frontend/package.json"
Assert-NotContains -Path $GamePackageJson -Unexpected '"vitest"'
Assert-NotContains -Path $GamePackageJson -Unexpected '"@vitest/coverage-v8"'
```

In both e2e tests, replace the current `^4.1.9` coverage assertion and add the
exact `vitest` assertion. The resulting assertions must be:

```powershell
Assert-Contains -Path $PackageJson -Expected '"@vitest/coverage-v8": "4.1.10"'
Assert-Contains -Path $PackageJson -Expected '"vitest": "4.1.10"'
```

```bash
assert_file_contains "$package_json_path" '"@vitest/coverage-v8": "4.1.10"'
assert_file_contains "$package_json_path" '"vitest": "4.1.10"'
```

Keep the existing literal `Contains`/substring assertion style, test ordering,
cleanup, and success messages unchanged.

- [ ] **Step 2: Run the focused tests to verify the expected RED state**

Run the PowerShell contract:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
```

Expected: exit nonzero at the new exact-version assertion because the current
generator still writes `^4.1.9`.

Run the Bash contract through the installed Git Bash executable:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: the Git Bash PowerShell subsection is skipped, then the Bash web
package assertion fails because the current generator still writes `^4.1.9`.

Do not change production generator lines until both focused assertions have
demonstrated this expected failure.

- [ ] **Step 3: Make the minimum generator changes**

In `new-project.ps1`, change only the two non-game web package entries:

```powershell
    "@vitest/coverage-v8": "4.1.10",
```

```powershell
    "vitest": "4.1.10"
```

In `new-project.sh`, change only the matching two escaped JSON entries:

```bash
    \"@vitest/coverage-v8\": \"4.1.10\",
```

```bash
    \"vitest\": \"4.1.10\"
```

Do not alter the existing `install --no-audit` call, the game package branch,
the generated README install, CI `npm ci`, or any other dependency line.

- [ ] **Step 4: Run the focused tests to verify GREEN**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: both exit 0. PowerShell prints `PowerShell web contract passed`;
Git Bash prints `Skipping PowerShell contract under Git Bash` and ends with
`cross-platform contract tests passed`. The fake npm logs still assert the
existing web/game argument sequences, and both contracts prove the game
package has no Vitest entries.

- [ ] **Step 5: Run syntax, parse, and command-shape checks**

Run the Bash syntax checks:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" -n new-project.sh
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" -n tests/cross_platform_contract.sh
```

Run PowerShell parsing and help:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\new-project.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | Format-List; exit 1 }'
pwsh -NoProfile -ExecutionPolicy Bypass -File new-project.ps1 -?
```

Expected: all commands exit 0 with no syntax errors.

- [ ] **Step 6: Run the real affected scaffold regressions**

Run the native PowerShell e2e that uses the real npm executable selected by the
generator:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1
```

Expected: npm no longer emits `Cannot read properties of null (reading
'edgesOut')`; the generated backend and frontend `check -> fix -> check`
sequence exits 0 and prints `PowerShell web scaffold e2e passed`.

Run the Bash e2e through Git Bash:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/scaffold_e2e.sh
```

Expected: the existing base and web e2e cases pass and the final line is
`all scaffold e2e tests passed`. The optional game case remains controlled by
`REPOSEED_E2E_GAME` and is not introduced or changed by this task.

- [ ] **Step 7: Verify the existing installer copies the corrected payload**

Use isolated temporary destinations so the user's current installed command is
not changed during repository verification:

```powershell
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reposeed-vitest-install-" + [System.Guid]::NewGuid().ToString("N"))
$BinDir = Join-Path $TempRoot "bin"
$DataDir = Join-Path $TempRoot "data"
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
try {
    & .\install.ps1 -BinDir $BinDir -DataDir $DataDir -Command reposeed-vitest-test
    $ManagedScript = Join-Path $DataDir "new-project.ps1"
    $Wrapper = Join-Path $BinDir "reposeed-vitest-test.ps1"
    if (-not (Test-Path -LiteralPath $ManagedScript)) { throw "Managed script was not copied." }
    if (-not (Test-Path -LiteralPath $Wrapper)) { throw "Wrapper was not created." }
    $ManagedText = Get-Content -Raw -LiteralPath $ManagedScript
    if (-not $ManagedText.Contains('"@vitest/coverage-v8": "4.1.10"')) { throw "Managed coverage version is stale." }
    if (-not $ManagedText.Contains('"vitest": "4.1.10"')) { throw "Managed Vitest version is stale." }
    if (-not $ManagedText.Contains('Invoke-Checked $NpmCommand install --no-audit')) { throw "Managed npm bootstrap is stale." }
    if (-not (Get-Content -Raw -LiteralPath $Wrapper).Contains("$DataDir")) { throw "Wrapper target is incorrect." }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
```

Expected: the isolated payload contains the corrected script and the wrapper
points to that payload; the user's `%LOCALAPPDATA%\RepoSeed` installation is
untouched.

- [ ] **Step 8: Inspect the final scope and preserved behavior**

Run:

```powershell
rg -n -C 2 '"@vitest/coverage-v8"|"vitest"|npm install|npm ci|--no-audit|playwright install' new-project.ps1 new-project.sh tests/powershell_web_contract.ps1 tests/cross_platform_contract.sh tests/scaffold_e2e.ps1 tests/scaffold_e2e.sh
git diff --check
```

Confirm:

- Only the two web Vitest entries change from caret `4.1.9` to exact `4.1.10`.
- Both web bootstrap calls still contain `--no-audit`.
- Game Playwright arguments are unchanged.
- README install strings and CI `npm ci` strings are unchanged.
- No `legacy-peer-deps`, `force`, `.npmrc`, npm selection, or unrelated profile change appears.
- All four existing web tests assert both exact package entries; the two fast
  contracts also prove the game package has no Vitest entries.

- [ ] **Step 9: Perform implementer self-review and final task verification**

Re-read the approved spec and this task against the final diff. Check exact
version alignment, changed callers and generated output, test fixture shapes,
temporary cleanup, npm argument preservation, installer scope, stale old-range
assertions, and unintended edits. Record either `no issues found` or each
issue found and fixed in the task report.

Before reporting the task complete, invoke
`superpowers:verification-before-completion` and rerun the exact focused,
syntax, parse/help, real e2e, installer-copy, scope, and diff checks above
against the final edit. No check may be left for a later task.

**Task Boundary Verification:**

- Focused PowerShell contract exits 0 and asserts exact web package values, game-package absence, and web/game npm calls.
- Focused Bash contract exits 0 and asserts exact web package values, game-package absence, and web/game npm calls.
- Bash syntax and PowerShell parser/help checks exit 0.
- PowerShell and Bash real web e2e checks exit 0 with their existing success messages.
- Isolated installer copy verification exits 0 and confirms corrected managed payload and wrapper target.
- `git diff --check` exits 0 apart from the pre-existing untouched CRLF warning, if it remains reported.
- Expected test changes: four existing web contract/e2e files gain exact Vitest pair assertions; no test files are created or removed; no production test count changes.
- Expected known failures: none at the final task boundary.
- Resulting state: both scaffolders emit exact aligned Vitest `4.1.10`, retain npm audit opt-out and all existing profile behavior, and the next stage may perform the final whole-branch review.

### Task 1 status

Implemented in commit `43b1b41` (exact `4.1.10` pair in both generators plus the four test-file assertion updates). Fast contracts, syntax/parse/help, and installer-copy checks pass at that commit; the real e2e still fails there because the pin alone cannot bypass npm 10's crashed peer loader. Tasks 2 and 3 below complete the fix; all three commits are reviewed together.

### Task 2 status

Implemented but uncommitted in the working tree (flag on both bootstrap calls plus the four npm-call assertion updates; exactly 6 changed lines). Fast contracts, syntax/parse/help pass in that state and the PowerShell real e2e exits 0, but the Bash real e2e fails because legacy resolution no longer auto-installs the `@testing-library/dom` peer. Task 3 below adds the explicit peer; Task 2 is committed together with Task 3 (one commit per task).

### Task 2: Bypass npm 10's Crashed Peer Loader on the Bootstrap Install

**Task Position**

- **Feature goal:** Fresh web scaffolds complete frontend installation on npm 10 without the Vitest peer-resolution crash.
- **Previously:** Task 1 (commit `43b1b41`) pins both generators to exact aligned Vitest `4.1.10` and proves the package output in all four web contract/e2e tests. Controller-verified root cause: bare `vitest@4.1.10` crashes npm 10.9.8 `#loadPeerSet` identically, while `--legacy-peer-deps` installs it cleanly, so the resolver itself is the fault and the bypass is the verified fix.
- **Current:** Add `--legacy-peer-deps` to the single shared web/game bootstrap install call in each generator, update the fake-npm call assertions to the new argument sequence, and prove the real npm 10 install plus managed payload.
- **Next:** Final whole-branch review will inspect the complete diff (Task 1 + Task 2) against the amended spec and rerun the final verification set.
- **Do not do yet:** Do not change `--force`, `.npmrc`, npm selection, installer implementation, CI `npm ci`, README install strings, lifecycle scripts, any dependency value, game behavior, non-web profiles, or historical artifacts.

**Files:**

- Modify: `new-project.ps1:596`, the shared web/game `Invoke-Checked $NpmCommand install --no-audit` call.
- Modify: `new-project.sh:1150`, the shared web/game `invoke_checked npm install --no-audit` call.
- Modify: `tests/powershell_web_contract.ps1:106-109,184-189`, existing web/game fake npm call assertions.
- Modify: `tests/cross_platform_contract.sh:224-229,244-248`, existing web/game fake npm call assertions.
- Modify: Task 1's installer-copy check expectation (already in this plan's Step 7 pattern): managed payload must contain `Invoke-Checked $NpmCommand install --no-audit --legacy-peer-deps`.

**Interfaces:**

- Consumes: Existing shared bootstrap calls, fake `npm` log assertions, real npm/uv e2e tools.
- Produces: Bootstrap argument sequence exactly `install --no-audit --legacy-peer-deps`; game follow-up unchanged (`exec playwright install chromium`).
- Preserves: Exact `4.1.10` Vitest pair, all generated check/CI/README/backend interfaces, nonzero exit propagation.

- [ ] **Step 1: Update the npm-call assertions first (RED)**

In `tests/powershell_web_contract.ps1`, change the web expectation from `"install --no-audit"` to `"install --no-audit --legacy-peer-deps"` and the game first-call expectation likewise; the game second call stays `"exec playwright install chromium"`. Keep the exact-count checks (`Count -ne 1` / `-ne 2`) unchanged.

In `tests/cross_platform_contract.sh`, change `"install --no-audit"` to `"install --no-audit --legacy-peer-deps"` in both the web single-call check and the game two-call check; the Playwright expectation stays unchanged.

Do not touch generator lines yet.

- [ ] **Step 2: Run the focused tests to verify RED**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: each fails on its npm-call assertion because the generators still emit `install --no-audit` without the flag.

- [ ] **Step 3: Make the minimum generator changes**

In `new-project.ps1`, line 596 becomes:

```powershell
Invoke-Checked $NpmCommand install --no-audit --legacy-peer-deps
```

In `new-project.sh`, line 1150 becomes:

```bash
invoke_checked npm install --no-audit --legacy-peer-deps
```

No other generator line changes.

- [ ] **Step 4: Run the focused tests to verify GREEN**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: both exit 0 with their existing success messages.

- [ ] **Step 5: Run syntax, parse, and command-shape checks** (same commands as Task 1 Step 5; all exit 0).

- [ ] **Step 6: Run the real affected scaffold regressions** (same commands as Task 1 Step 6). Expected now: `tests\scaffold_e2e.ps1` completes the real npm 10 install without `edgesOut` and prints `PowerShell web scaffold e2e passed`; `tests/scaffold_e2e.sh` ends `all scaffold e2e tests passed`. If either still fails, stop and escalate — do not stack further workarounds.

- [ ] **Step 7: Verify the existing installer copies the corrected payload** using Task 1's Step 7 script, except the bootstrap assertion becomes:

```powershell
if (-not $ManagedText.Contains('Invoke-Checked $NpmCommand install --no-audit --legacy-peer-deps')) { throw "Managed npm bootstrap is stale." }
```

The user's `%LOCALAPPDATA%\RepoSeed` installation stays untouched.

- [ ] **Step 8: Inspect the final scope and preserved behavior** using Task 1's Step 8 search. Confirm: only the two Vitest values plus the one bootstrap flag per generator changed; game Playwright args, README install strings, and CI `npm ci` strings unchanged; no `--force`, `.npmrc`, npm selection, or unrelated profile change appears.

- [ ] **Step 9: Perform implementer self-review and final task verification** per Task 1 Step 9, covering both Task 1 and Task 2 changes against the amended spec.

**Task Boundary Verification:**

- Focused PowerShell and Bash contracts exit 0 and assert the `install --no-audit --legacy-peer-deps` sequence plus the exact `4.1.10` pair and Vitest-free game package.
- Bash syntax and PowerShell parser/help checks exit 0.
- PowerShell and Bash real web e2e checks exit 0 with their existing success messages.
- Isolated installer copy verification exits 0 and confirms the managed payload has the `4.1.10` pair and the flagged bootstrap call.
- `git diff --check` exits 0 apart from the pre-existing untouched CRLF warning, if still reported.
- Expected test changes: two contract files gain the flag in their npm-call assertions (Task 1's version assertions already in place); no test files created or removed.
- Expected known failures: none at the final task boundary.
- Resulting state: both scaffolders emit exact aligned Vitest `4.1.10` and bootstrap with `install --no-audit --legacy-peer-deps`; the next stage performs the final whole-branch review.

### Task 3: Declare the `@testing-library/dom` Peer Explicitly

**Task Position**

- **Feature goal:** Fresh web scaffolds complete frontend installation on npm 10 without the Vitest peer-resolution crash.
- **Previously:** Task 1 (commit `43b1b41`) pins exact Vitest `4.1.10`. Task 2 (uncommitted working tree, 6 lines) adds `--legacy-peer-deps` to both bootstrap calls and updates the four npm-call assertions; fast contracts and the PowerShell real e2e pass there, but the Bash real e2e fails with `Cannot find module '@testing-library/dom'`. Controller-verified root cause from registry metadata: every `@testing-library/react@16` declares `'@testing-library/dom': '^10.0.0'` as a peer and no `jest-dom@6` lists it as a regular dependency, so legacy mode installs nothing for it.
- **Current:** Add `"@testing-library/dom": "^10.0.0"` to both web `devDependencies` blocks (alphabetical slot before `@testing-library/jest-dom`), assert it in all four web contract/e2e tests, commit Task 2 and Task 3 as separate commits, and prove both real e2es exit 0.
- **Next:** Final whole-branch review will inspect the complete diff (Tasks 1-3) against the amended spec and rerun the final verification set.
- **Do not do yet:** Do not change `--force`, `.npmrc`, npm selection, installer implementation, CI `npm ci`, README install strings, lifecycle scripts, any other dependency value, game behavior, non-web profiles, or historical artifacts.

**Files:**

- Modify: `new-project.ps1:353` (insert before the `@testing-library/jest-dom` line).
- Modify: `new-project.sh:678` (insert before the escaped `@testing-library/jest-dom` line).
- Modify: `tests/powershell_web_contract.ps1`, `tests/cross_platform_contract.sh`, `tests/scaffold_e2e.ps1`, `tests/scaffold_e2e.sh` — add the dom assertion next to the existing exact-version assertions.
- Commit: Task 2's 6 working-tree lines as one commit, then Task 3's changes as a second commit. Do not push.

**Interfaces:**

- Consumes: Existing web `devDependencies` blocks, literal `Contains`/substring assertion helpers, real npm/uv e2e tools.
- Produces: Generated web package line exactly `"@testing-library/dom": "^10.0.0"`.
- Preserves: Exact `4.1.10` pair, flagged bootstrap sequence, game/Vitest-free package, CI/README/backend interfaces.

- [ ] **Step 1: Add the dom assertions first (RED)**

In `tests/powershell_web_contract.ps1` and `tests/scaffold_e2e.ps1`, add next to the `4.1.10` assertions:

```powershell
Assert-Contains -Path $PackageJson -Expected '"@testing-library/dom": "^10.0.0"'
```

In `tests/cross_platform_contract.sh` (next to the web `4.1.10` assertions) and `tests/scaffold_e2e.sh` (in `assert_web_frontend_config`), add:

```bash
assert_file_contains "$project_dir/frontend/package.json" '"@testing-library/dom": "^10.0.0"'
```

using each file's existing package-path variable. Do not touch generator lines yet.

- [ ] **Step 2: Run the focused tests to verify RED**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: each fails on the new dom assertion because the generators do not emit it yet.

- [ ] **Step 3: Make the minimum generator changes**

In `new-project.ps1`, insert alphabetically before the jest-dom line:

```powershell
    "@testing-library/dom": "^10.0.0",
```

In `new-project.sh`, insert the escaped equivalent before the jest-dom line:

```bash
    \"@testing-library/dom\": \"^10.0.0\",
```

No other generator line changes.

- [ ] **Step 4: Run the focused tests to verify GREEN** (same two commands; both exit 0 with existing success messages).

- [ ] **Step 5: Run syntax, parse, and command-shape checks** (same commands as Task 1 Step 5; all exit 0).

- [ ] **Step 6: Run the real affected scaffold regressions** (same commands as Task 1 Step 6). Expected now: both `tests\scaffold_e2e.ps1` (`PowerShell web scaffold e2e passed`) and `tests/scaffold_e2e.sh` (`all scaffold e2e tests passed`) exit 0 — the Bash web `check.sh` vitest run must find `@testing-library/dom`. If either still fails, stop and report BLOCKED with the error — do not stack further workarounds.

- [ ] **Step 7: Verify the existing installer copies the corrected payload** using Task 1's Step 7 script with Task 2's flagged bootstrap assertion, plus:

```powershell
if (-not $ManagedText.Contains('"@testing-library/dom": "^10.0.0"')) { throw "Managed testing-library version is stale." }
```

The user's `%LOCALAPPDATA%\RepoSeed` installation stays untouched.

- [ ] **Step 8: Inspect the final scope and preserved behavior** using Task 1's Step 8 search (extend the pattern with `testing-library/dom`). Confirm: only the two Vitest values, the one bootstrap flag per generator, and the one dom line per generator changed; game Playwright args, README install strings, and CI `npm ci` strings unchanged; no `--force`, `.npmrc`, npm selection, or unrelated profile change appears.

- [ ] **Step 9: Commit as two task commits, then self-review and verify**

Commit Task 2's pre-existing 6 working-tree lines first (message like `fix(web): bypass crashed npm 10 peer loader on bootstrap install`), then Task 3's changes (message like `fix(web): declare testing-library/dom peer explicitly`). Do not push. Then perform implementer self-review of the combined Tasks 1-3 diff against the amended spec and rerun the full verification set against the final state before reporting.

**Task Boundary Verification:**

- Focused PowerShell and Bash contracts exit 0 and assert the `4.1.10` pair, the dom `^10.0.0` line, the flagged bootstrap sequence, and the Vitest-free game package.
- Bash syntax and PowerShell parser/help checks exit 0.
- PowerShell and Bash real web e2e checks exit 0 with their existing success messages.
- Isolated installer copy verification exits 0 and confirms the managed payload has the `4.1.10` pair, the dom line, and the flagged bootstrap call.
- `git diff --check` (or `git status` + `git diff --check` on the final state) is clean apart from the pre-existing untouched CRLF warning, if still reported.
- Expected test changes: four contract/e2e files assert the dom line; no test files created or removed.
- Expected known failures: none at the final task boundary.
- Resulting state: both scaffolders emit exact Vitest `4.1.10`, explicit dom `^10.0.0`, and bootstrap with `install --no-audit --legacy-peer-deps`; the next stage performs the final whole-branch review.

## Final Plan Audit

- Every spec acceptance scenario maps to a concrete assertion or direct command across Tasks 1-3.
- Every planned file exists and every referenced symbol/line was revalidated against the current checkout (dev blocks `new-project.ps1:350-369`, `new-project.sh:675-694`; call sites `new-project.ps1:596`, `new-project.sh:1150` read directly).
- Task 1 is committed; Task 2 is implemented-uncommitted with passing fast checks; Task 3 owns only the dom line and its assertions, then commits Task 2 and Task 3 separately.
- No task introduces a public option, global config, or unrelated cleanup; the flag is the user-authorized crash fix and the dom line is its verified required peer, both evidenced from the registry before planning.
- The implementation decision load is mechanical: insert the named line in the named slot, update named literal assertions, and run the named commands.
- The planned final state was checked for stale `^4.1.9` assertions, unchanged CI/README/game paths, syntax/tooling conformance, and green task boundaries.
