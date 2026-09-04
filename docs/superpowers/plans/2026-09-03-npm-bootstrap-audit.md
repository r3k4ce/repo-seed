# npm Bootstrap Audit Opt-Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the initial frontend dependency install in both RepoSeed scaffolders finish without waiting for npm's optional security-audit request.

**Architecture:** Keep the existing Bash and PowerShell scaffolders independent. Add npm's native `--no-audit` option only to their shared initial web/game install calls, and extend the existing fake-command contract tests to verify the exact arguments passed at runtime.

**Tech Stack:** Bash, PowerShell 7, npm, uv, Git Bash on Windows for Bash verification, existing contract and scaffold e2e tests.

**Spec:** `docs/superpowers/specs/2026-09-03-npm-bootstrap-audit-design.md`

## Global Constraints

- Initial web/game frontend install commands must be exactly `npm install --no-audit` or the PowerShell equivalent using `$NpmCommand`.
- Do not change generated dependency versions, lockfile contents, lifecycle scripts, or the ESLint 9 warning.
- Do not change generated README setup commands, GitHub Actions `npm ci`, npm user configuration, or npm timeout/retry settings.
- Keep the existing `npm exec playwright install chromium` game command unchanged.
- Keep base and desktop profiles unchanged.
- Keep existing checked-command error propagation unchanged.
- Use the existing fake-command contract tests; add no test framework, dependency, abstraction, or new test file.
- Under Git Bash, skip only the existing cross-platform test's PowerShell subsection; native PowerShell coverage remains in `tests/powershell_web_contract.ps1`.
- Planning context: branch `main`, HEAD `238f00520f8c8a9b4d1762788aa5da640aaaf926`; no parent/return branch was recorded.
- Baseline evidence: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1` passed; `pwsh -NoProfile -ExecutionPolicy Bypass -File new-project.ps1 -?` passed; `git diff --check` exited 0; the existing Bash cross-platform contract reaches its Bash checks but fails only in its PowerShell subsection under Git Bash because the fake `uv` does not set PowerShell's `$LASTEXITCODE`.

---

## File Map

| File | Action | Responsibility |
| --- | --- | --- |
| `new-project.ps1` | Modify | Pass `--no-audit` to the shared initial web/game frontend install. |
| `new-project.sh` | Modify | Pass `--no-audit` to the shared initial web/game frontend install. |
| `tests/powershell_web_contract.ps1` | Modify | Record fake npm arguments and verify web/game call sequences while retaining the existing web artifact assertions. |
| `tests/cross_platform_contract.sh` | Modify | Record fake npm arguments for Bash web/game scaffolds and skip the incompatible PowerShell subsection under Git Bash. |
| `docs/superpowers/specs/2026-09-03-npm-bootstrap-audit-design.md` | Create | Binding behavior, boundaries, acceptance scenarios, and test strategy. |
| `docs/superpowers/plans/2026-09-03-npm-bootstrap-audit.md` | Create | This task-by-task implementation and verification plan. |

No installer, README, CHANGELOG, frontend template, CI, or generated-project file is modified by the implementation task.

---

### Task 1: Disable npm Audit During Bootstrap Installs

**Task Position**

- **Feature goal:** Web and game scaffolding completes the initial frontend install without waiting for npm's advisory service.
- **Previously:** The verified baseline is branch `main` at `238f00520f8c8a9b4d1762788aa5da640aaaf926`. The PowerShell web contract and command-help check pass. The current source calls bare `install`; the installed `reposeed.ps1` is a separate stale managed copy and is not modified by this task.
- **Current:** Make both scaffolders pass `install --no-audit`, prove the exact web/game fake npm calls, and make the existing Bash cross-platform contract truthful under Git Bash.
- **Next:** Final whole-branch review will inspect the complete diff against the spec and rerun full verification on the reviewed state.
- **Do not do yet:** Do not upgrade ESLint, change dependency ranges, edit generated README or CI `npm ci`, change npm configuration, modify installers, or alter Playwright behavior.

**Files:**

- Modify: `tests/powershell_web_contract.ps1:44-99` for the temporary npm argument log and fake command.
- Modify: `tests/powershell_web_contract.ps1:101-162` for the web/game argument assertions and environment cleanup.
- Modify: `tests/cross_platform_contract.sh:29-72` for the fake Bash npm command.
- Modify: `tests/cross_platform_contract.sh:74-188` for the web/game contract and the MINGW/MSYS PowerShell skip.
- Modify: `new-project.ps1:594-613` for the shared web/game install call.
- Modify: `new-project.sh:1147-1154` for the shared web/game install call.

**Interfaces:**

- Consumes: Existing `new-project.ps1 -Name <name> -Profile <web|game> -NoGit -NoInstallHooks -NoGitHubActions`, existing `new-project.sh --name <name> --profile <web|game> --no-git --no-install-hooks --no-github-actions`, and the existing fake `uv` commands.
- Produces: PowerShell call `$NpmCommand install --no-audit`, Bash call `npm install --no-audit`, and fake npm log lines with one invocation per line.
- Web log contract: exactly `install --no-audit`.
- Game log contract: exactly `install --no-audit` followed by exactly `exec playwright install chromium`.
- Failure contract: the existing `Invoke-Checked` and `invoke_checked` helpers remain responsible for returning npm's nonzero status.

- [ ] **Step 1: Extend the PowerShell fake npm with argument recording**

In `tests/powershell_web_contract.ps1`, preserve the current temporary-root setup and add a temporary log path plus an environment-variable save before the `try` block:

```powershell
$OriginalNpmLog = $env:REPOSEED_TEST_NPM_LOG
```

After `$TmpRoot` and `$BinDir` are created, add:

```powershell
$NpmLog = Join-Path $TmpRoot "npm-args.log"
$env:REPOSEED_TEST_NPM_LOG = $NpmLog
```

Replace the current fake `npm.cmd` body with this exact body so `%*` records the received arguments and the command still succeeds:

```powershell
Set-Content -LiteralPath (Join-Path $BinDir "npm.cmd") -Value @"
@echo off
>> "%REPOSEED_TEST_NPM_LOG%" echo %*
exit /b 0
"@
```

Keep the fake `uv.cmd` and all existing web artifact assertions unchanged.

- [ ] **Step 2: Extend the Bash contract with a fake npm and platform skip**

In `tests/cross_platform_contract.sh`, add this helper after `prepend_fake_uv`:

```bash
prepend_fake_npm() {
  local fake_bin="$1"
  local log_path="$2"

  cat >"$fake_bin/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$*" >>"$log_path"
EOF
  chmod +x "$fake_bin/npm"
}
```

At the beginning of `run_powershell_contract_if_available`, before the current `pwsh` availability check, add this Git Bash-only skip:

```bash
  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    printf 'Skipping PowerShell contract under Git Bash\\n'
    return
  fi
```

This changes only test selection in the cross-shell harness. The dedicated
native PowerShell contract remains the PowerShell verification path.

- [ ] **Step 3: Add failing assertions for both fake npm call sequences**

Add `run_bash_web_and_game_install_contract` before the existing final function calls in `tests/cross_platform_contract.sh`. It must:

1. Create `tmp_root`, `project_dir`, and `log_path` with `mktemp -d`.
2. Call `prepend_fake_uv "$tmp_root/bin"` and `prepend_fake_npm "$tmp_root/bin" "$log_path"`.
3. Create `project_dir`, run the Bash generator from inside it with:

```bash
"$ROOT/new-project.sh" \
  --profile web \
  --name bash-web-install-contract \
  --no-git \
  --no-install-hooks \
  --no-github-actions
```

4. Assert `"$project_dir/README.md"` exists, read `log_path` into an array, and fail unless it has one item equal to `install --no-audit`.
5. Truncate `log_path`, create a second project, and run:

```bash
"$ROOT/new-project.sh" \
  --profile game \
  --name bash-game-install-contract \
  --no-git \
  --no-install-hooks \
  --no-github-actions
```

6. Read the second log and fail unless it has exactly two items equal, in order,
   to `install --no-audit` and `exec playwright install chromium`.
7. Call `run_bash_web_and_game_install_contract` at the bottom of the script.

In `tests/powershell_web_contract.ps1`, after the existing web scaffold returns
and before the existing web artifact assertions, add this red assertion:

```powershell
$WebNpmCalls = @(Get-Content -LiteralPath $NpmLog)
if ($WebNpmCalls.Count -ne 1 -or $WebNpmCalls[0] -ne "install --no-audit") {
    throw "Expected web npm call install --no-audit, got: $($WebNpmCalls -join ', ')"
}
```

After the existing web assertions, clear the log, scaffold a separate game
project with the same fake commands using `-Profile game -NoGit -NoInstallHooks
-NoGitHubActions`, and add this exact assertion:

```powershell
$GameNpmCalls = @(Get-Content -LiteralPath $NpmLog)
if ($GameNpmCalls.Count -ne 2 -or
    $GameNpmCalls[0] -ne "install --no-audit" -or
    $GameNpmCalls[1] -ne "exec playwright install chromium") {
    throw "Expected game npm calls install --no-audit then Playwright install, got: $($GameNpmCalls -join ', ')"
}
```

The existing `finally` block must restore `$env:Path`, restore
`$env:REPOSEED_TEST_NPM_LOG` when it existed, remove it when it did not, and
delete `$TmpRoot` exactly as it does for the existing temporary state.

- [ ] **Step 4: Run the new tests to verify the expected RED state**

Run the PowerShell contract:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
```

Expected: FAIL at the new web argument assertion because the current generator
records `install`, not `install --no-audit`.

Run the Bash contract through the discovered Git Bash executable:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: the Bash base and installer checks run, the PowerShell subsection is
skipped with `Skipping PowerShell contract under Git Bash`, and the new Bash web
argument assertion fails because the current generator records `install`.

Do not change production code before both new assertions have demonstrated this
failure.

- [ ] **Step 5: Make the minimum production changes**

Change only the existing initial frontend install calls:

In `new-project.ps1`, change the shared web/game block from:

```powershell
Invoke-Checked $NpmCommand install
```

to:

```powershell
Invoke-Checked $NpmCommand install --no-audit
```

In `new-project.sh`, change the shared web/game block from:

```bash
invoke_checked npm install
```

to:

```bash
invoke_checked npm install --no-audit
```

Do not change the generated README `npm install`, any `npm ci` string, the game
Playwright command, package definitions, or checked-command helper bodies.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
```

Expected: exit 0 and the existing `PowerShell web contract passed` success
message. Keep that message unchanged even though the test also verifies the
shared game install path.

Run:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh
```

Expected: exit 0, the Git Bash PowerShell subsection is skipped, and the final
line is `cross-platform contract tests passed`.

- [ ] **Step 7: Run syntax and affected regression checks**

Run Bash syntax checks:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" -n new-project.sh
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" -n tests/cross_platform_contract.sh
```

Expected: both exit 0 with no output.

Run PowerShell parsing and command help:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\new-project.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | Format-List; exit 1 }'
pwsh -NoProfile -ExecutionPolicy Bypass -File new-project.ps1 -?
```

Expected: both exit 0.

Run the native real-install regression:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1
```

Expected: exit 0 and `PowerShell web scaffold e2e passed`; the real npm
bootstrap returns and the generated check/fix/check sequence completes.

Run the Bash real-install regression from Git Bash:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/scaffold_e2e.sh
```

Expected: exit 0 with base and web scaffold e2e success. The existing optional
game path remains available through `REPOSEED_E2E_GAME=1` and is not required
for this web regression boundary.

- [ ] **Step 8: Inspect the final diff and verify the scope boundary**

Run:

```powershell
rg -n -C 2 'npm install|npm ci|--no-audit|playwright install' new-project.ps1 new-project.sh tests/powershell_web_contract.ps1 tests/cross_platform_contract.sh
```

Confirm from the diff that:

- Only the two initial install calls gain `--no-audit`.
- The generated README strings and CI `npm ci` strings remain unchanged.
- The game Playwright command remains unchanged.
- The test logs assert exact arguments rather than only checking source text.
- The MINGW/MSYS skip is limited to the existing PowerShell subsection of the
  cross-platform test.

- [ ] **Step 9: Mandatory implementer self-review and final task verification**

Re-read this task and the spec against the final diff. Check the web and game
argument sequences, nonzero exit propagation, stale imports or variables,
temporary-file cleanup, unchanged CI/README behavior, naming, and unintended
edits. Record either `no issues found` or each issue found and fixed in the task
report.

Before reporting the task done, invoke `superpowers:verification-before-completion`
and rerun the exact focused, syntax, help, and affected regression commands from
Steps 6 and 7 against the final edit. The task must end with all applicable
checks green and no known failures.

**Task Boundary Verification:**

- Focused PowerShell: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1` -> exit 0, exact web and game npm call assertions pass.
- Focused Bash: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` -> exit 0, Bash web and game call assertions pass, Git Bash skips only the incompatible PowerShell subsection.
- Syntax: both `bash.exe -n` commands and PowerShell parser command -> exit 0.
- Command shape: `pwsh -NoProfile -ExecutionPolicy Bypass -File new-project.ps1 -?` -> exit 0.
- Affected regression: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1` and Git Bash `tests/scaffold_e2e.sh` -> exit 0 with their existing success messages.
- Expected test changes: two existing contract tests gain bootstrap argument coverage; no test files are created or removed; existing artifact assertions remain.
- Expected known failures: none.
- Resulting state: both scaffolders use native npm audit opt-out only for bootstrap installs; CI, README, package definitions, installers, and unrelated profiles remain unchanged. The next task may assume the exact call contracts and real web e2e are green.

## Final Plan Audit

- Every spec acceptance scenario maps to the exact fake npm assertions, existing checked-command behavior, or the explicit CI/non-web source checks in Task 1.
- The plan has one implementation task because both production call sites and their contract tests form one small, behaviorally coupled change.
- No production dependency, public option, persisted data, or unrelated documentation is introduced.
- The only environment-specific test adjustment is the documented MINGW/MSYS skip for a pre-existing cross-shell false failure.
- The implementation agent has no remaining product, interface, naming, test-intent, or architecture decisions.
