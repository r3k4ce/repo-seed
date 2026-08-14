# PowerShell Web Profile Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `new-project.ps1 -Profile web` generate the same frontend tooling and quality gates as the Bash web profile.

**Architecture:** Keep the two generators separate. Copy Bash web values into the PowerShell web branch and create native PowerShell contract and e2e tests; do not refactor shared generator content.

**Tech Stack:** PowerShell 7, uv, npm, React 19, Vite 7, Tailwind 4.3.2, Vitest 4.1.9 with v8 coverage, TypeScript, ESLint.

## Global Constraints

- Change only PowerShell `web` output; do not change `base`, `desktop`, `game`, or Bash behavior.
- Match Bash web versions, dependency groups, scripts, Tailwind plugin, v8 coverage, 80% thresholds, and exclusions exactly.
- Web checks require `test`, `typecheck`, `lint`, then `build`; they never run browser tests.
- Game keeps its existing optional test and Playwright behavior.
- Do not add dependencies, templates, or abstractions.
- New PowerShell tests remove temporary files even after failure.
- Planning context: `main` at `153c6e2c5b08d2852df4b8e5cfeee9a5be9270b3`; no parent branch recorded.
- Baseline: `new-project.ps1 -?` passes. Bash tests cannot run here because `bash.exe` requires a WSL distribution that is not installed.

---

## File Map

| File | Action | Responsibility |
| --- | --- | --- |
| `new-project.ps1` | Modify | Generate Bash-parity web artifacts, checks, and CI. |
| `tests/powershell_web_contract.ps1` | Create | Fast native contract using fake `uv` and `npm` commands. |
| `tests/scaffold_e2e.ps1` | Create | Full native scaffold and generated check/fix/check test. |

## Task 1: Match Web Generation and Add a Fast Contract

**Task Position**

- **Feature goal:** Windows-created web projects use the same frontend tools and required checks as Bash-created web projects.
- **Previously:** Baseline is the planning commit above; only the PowerShell command help has been verified locally.
- **Current:** Add a fake-command contract, then make PowerShell web output satisfy it.
- **Next:** Add real dependency-installing e2e coverage.
- **Do not do yet:** Do not modify Bash, game, base, desktop, or add the e2e test.

**Files:**

- Create: `tests/powershell_web_contract.ps1`
- Modify: `new-project.ps1:340-376` (web `package.json`)
- Modify: `new-project.ps1:486-505` (web Vite config)
- Modify: `new-project.ps1:690-770` (web/game generated PowerShell scripts)
- Modify: `new-project.ps1:831-906` (web/game generated CI)

**Interfaces:**

- Consumes: `new-project.ps1 -Name <name> -Profile web -NoGit -NoInstallHooks`.
- Produces: web `package.json`, `vite.config.ts`, `check.ps1`, `fix.ps1`, and CI content verified by `tests/powershell_web_contract.ps1`.

- [ ] **Step 1: Write the failing contract test**

Create `tests/powershell_web_contract.ps1` with `$ErrorActionPreference = "Stop"`, `Assert-Contains`, `Assert-NotContains`, and `Assert-InOrder` helpers. `Assert-InOrder` reads the file once, finds each expected string using increasing `IndexOf` offsets, and throws when a string is absent or appears before its predecessor.

In `try/finally`, create a temporary root and a `bin` folder; prepend it to `$env:Path`; write these fake batch commands:

```bat
:: npm.cmd
@echo off
exit /b 0

:: uv.cmd
@echo off
if /I not "%~1"=="init" exit /b 0
set "package=python_project"
set "project=."
:parse
shift
if "%~1"=="" goto create
if /I "%~1"=="--name" (
  set "package=%~2"
) else if /I "%~1"=="--python" (
  shift
) else if /I "%~1"=="--vcs" (
  shift
) else if /I not "%~1"=="--package" (
  set "project=%~1"
)
goto parse
:create
set "package=%package:-=_%"
mkdir "%project%\src\%package%"
> "%project%\pyproject.toml" echo [project]
exit /b 0
```

Run the real generator with `-Name ps-web-contract -Profile web -NoGit -NoInstallHooks`. Restore `$env:Path` and delete the temporary root in `finally`.

Assert these exact conditions:

```text
package.json contains:
  "react": "^19.0.0"
  "tailwindcss": "^4.3.2"
  "@tailwindcss/vite": "^4.3.2"
  "@vitest/coverage-v8": "^4.1.9"
  "test": "vitest run --coverage"
  "test:watch": "vitest"
package.json does not contain: "latest", @playwright/test, test:e2e

vite.config.ts contains:
  import tailwindcss from "@tailwindcss/vite";
  plugins: [react(), tailwindcss()]
  provider: "v8"
  statements: 80
  branches: 80
  functions: 80
  lines: 80
  "src/main.tsx"
  "src/vite-env.d.ts"
  "src/test/**"
  "**/*.test.{ts,tsx}"

check.ps1 and fix.ps1 pass Assert-InOrder for:
  Invoke-Checked $Npm run test
  Invoke-Checked $Npm run typecheck
  Invoke-Checked $Npm run lint
  Invoke-Checked $Npm run build
check.ps1 and fix.ps1 do not contain: --if-present, test:e2e

.pre-commit-config.yaml contains:
  powershell -ExecutionPolicy Bypass -File scripts/check.ps1

ci.yml contains:
  - name: Frontend test
  run: npm run test
  - name: Frontend typecheck
  run: npm run typecheck
ci.yml does not contain: Install Playwright Chromium, test:e2e
```

- [ ] **Step 2: Run the contract to prove it is red**

Run:

```powershell
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
```

Expected: failure because PowerShell web `package.json` contains `"latest"` and lacks the required Tailwind and coverage entries.

- [ ] **Step 3: Make the smallest generator changes that satisfy the contract**

Update the non-game web `package.json` here-string to exactly match Bash web's `frontend/package.json`:

```json
"scripts": {
  "dev": "vite",
  "build": "tsc -b && vite build",
  "lint": "eslint .",
  "typecheck": "tsc --noEmit",
  "test": "vitest run --coverage",
  "test:watch": "vitest",
  "preview": "vite preview"
},
"dependencies": {
  "react": "^19.0.0",
  "react-dom": "^19.0.0"
}
```

Set `devDependencies` exactly to:

```json
{
  "@eslint/js": "^9.0.0",
  "@tailwindcss/vite": "^4.3.2",
  "@testing-library/jest-dom": "^6.0.0",
  "@testing-library/react": "^16.0.0",
  "@types/react": "^19.0.0",
  "@types/react-dom": "^19.0.0",
  "@vitejs/plugin-react": "^5.0.0",
  "@vitest/coverage-v8": "^4.1.9",
  "eslint": "^9.0.0",
  "eslint-plugin-react-hooks": "^7.0.0",
  "eslint-plugin-react-refresh": "^0.4.0",
  "globals": "^16.0.0",
  "jsdom": "^27.0.0",
  "tailwindcss": "^4.3.2",
  "typescript": "^5.9.0",
  "typescript-eslint": "^8.0.0",
  "vite": "^7.0.0",
  "vitest": "^4.1.9"
}
```

Replace the web Vite here-string with exactly:

```ts
import { defineConfig } from "vitest/config";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    chunkSizeWarningLimit: 2000,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8000",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,
      },
      exclude: [
        "src/main.tsx",
        "src/vite-env.d.ts",
        "src/test/**",
        "**/*.test.{ts,tsx}",
      ],
    },
  },
});
```

Split the shared web/game PowerShell check and fix here-strings on
`$Profile -eq "game"`:

```powershell
# web frontend sequence in both generated files
Invoke-Checked $Npm run test
Invoke-Checked $Npm run typecheck
Invoke-Checked $Npm run lint
Invoke-Checked $Npm run build
```

Keep the current game sequence unchanged: `test --if-present`, `test:e2e
--if-present`, lint, build.

Split generated CI on the same condition. Preserve the current CI for game.
For web, keep the existing backend steps and Node setup, then emit exactly:

```yaml
- name: Frontend test
  working-directory: frontend
  run: npm run test
- name: Frontend typecheck
  working-directory: frontend
  run: npm run typecheck
- name: Frontend lint
  working-directory: frontend
  run: npm run lint
- name: Frontend build
  working-directory: frontend
  run: npm run build
```

Do not emit a Playwright install or browser-test step in web CI.

- [ ] **Step 4: Verify the green contract and inspect the diff**

Run the contract command from Step 2. Expected: `PowerShell web contract passed` with exit code 0.

Inspect `git diff -- new-project.ps1 tests/powershell_web_contract.ps1`.
Confirm all changes are in the web branch except the explicit game-preserving conditional, and the fake commands exist only in the test.

**Task Boundary Verification:**

- Focused red/green command: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1`; red before Step 3, passes after it.
- Affected regression: `pwsh -NoProfile -File new-project.ps1 -?`; expected pass.
- Formatting/lint/type/build: none configured for this repository's own PowerShell scripts.
- Expected test inventory: one new fast PowerShell contract script; known failures: none.
- Resulting state: the next task can rely on a web generator whose artifacts satisfy the static parity contract.

## Task 2: Add Native PowerShell Web Scaffold E2E Coverage

**Task Position**

- **Feature goal:** Windows-created web projects use the same frontend tools and required checks as Bash-created web projects.
- **Previously:** Task 1 made generated artifacts pass the fake-command contract.
- **Current:** Prove a real PowerShell-created web project installs and passes its generated checks before and after its fixer.
- **Next:** Final whole-branch verification follows.
- **Do not do yet:** Do not expand test coverage to game, desktop, or Bash profiles.

**Files:**

- Create: `tests/scaffold_e2e.ps1`
- Modify: none

**Interfaces:**

- Consumes: real `uv`, `npm`/`npm.cmd`, `new-project.ps1`, and the Task 1 web output contract.
- Produces: an executable native Windows regression gate with exit code 0 only when the generated project checks pass.

- [ ] **Step 1: Demonstrate the missing e2e entrypoint**

Run:

```powershell
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1
```

Expected: PowerShell reports that `tests\scaffold_e2e.ps1` does not exist.

- [ ] **Step 2: Write the native e2e test**

Create `tests/scaffold_e2e.ps1` with `$ErrorActionPreference = "Stop"`.
Require `uv`, then resolve npm with the same preference as the generator:

```powershell
$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { throw "uv is required" }
if (-not (Get-Command $Npm -ErrorAction SilentlyContinue)) { throw "npm is required" }
```

Use a `try/finally` temporary root. Run:

```powershell
& $Scaffolder -Name "powershell-web-e2e" -Profile web -NoGit -NoInstallHooks
& (Join-Path $ProjectDir "scripts/check.ps1")
& (Join-Path $ProjectDir "scripts/fix.ps1")
& (Join-Path $ProjectDir "scripts/check.ps1")
```

Before the generated scripts run, assert the same generated file contract from
Task 1 (including CI) with local `Assert-Contains` and `Assert-NotContains`
helpers. Use `Push-Location $ProjectDir` and `Pop-Location` in `finally` so
the generated scripts find `backend` and `frontend`. Always remove the
temporary root in the outer `finally`. Print `PowerShell web scaffold e2e
passed` only after the final check exits successfully.

- [ ] **Step 3: Run the full e2e and regressions**

Run:

```powershell
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -File new-project.ps1 -?
```

Expected: e2e reports success after two generated check runs and one generated
fix run; the static contract and help command also exit 0.

**Task Boundary Verification:**

- Focused e2e command: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\scaffold_e2e.ps1`; expected pass.
- Affected regression command: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1`; expected pass.
- Smoke command: `pwsh -NoProfile -File new-project.ps1 -?`; expected pass.
- Formatting/lint/type/build: the generated project's check/fix/check sequence runs frontend coverage, type checking, linting, and build; expected all pass.
- Expected test inventory: two new native PowerShell test scripts; known failures: none.
- Resulting state: PowerShell web parity is implemented and verified; final whole-branch review can begin.

## Acceptance Coverage Map

| Spec behavior | Evidence |
| --- | --- |
| Pinned web dependencies, Tailwind, coverage, no Playwright | Task 1 contract `package.json` assertions; Task 2 repeated assertions. |
| Vite plugins, v8 coverage, 80% thresholds | Task 1 contract Vite assertions; Task 2 repeated assertions. |
| Required web check/fix order without browser tests | Task 1 generated-script assertions; Task 2 executes check/fix/check. |
| Web CI test/typecheck/lint/build without Playwright | Task 1 and Task 2 CI assertions. |
| Fast native PowerShell contract | Task 1 green command. |
| Real Windows scaffold passes its checks | Task 2 full e2e green command. |

## Exclusions

- No web UI or CSS behavior changes.
- No generated project migration.
- No game, desktop, base, installer, or Bash scaffold changes.
