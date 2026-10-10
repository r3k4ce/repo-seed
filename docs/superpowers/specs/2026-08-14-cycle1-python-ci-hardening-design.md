# Cycle 1: Python + CI Hardening — Design Spec

Date: 2026-08-14
Status: Approved at Gate 1 (brainstorm handoff) — spec for Gate 2
Baseline: branch `main`, commit `238f005`

## Problem

Every project RepoSeed generates today gates on formatting, linting, static
types, and tests — but nothing else. Concretely, a freshly scaffolded project:

- has no dependency-vulnerability check (`uv audit` is built into uv and free),
- never verifies its own lockfile is current (`uv lock --check`),
- never scans for committed secrets,
- uses a curated ruff rule set that omits security and dead-code rules,
- pins CI actions by tag (`@v6`), which is trivially hijackable,
- does not lint its own GitHub Actions workflow files,
- has no automated dependency-update PRs,
- ships no shared editor settings and no security policy stub.

## Goal

After this cycle, every generated project (all profiles, both platforms) gets
these floor-raisers by default, with two new opt-out flags, and all existing
contract/e2e tests keep passing plus new ones cover the added content.

## Scope

In scope (all profiles: `base`, `desktop` (PowerShell-only), `web`, `game`):

1. Ruff config additions in generated `pyproject.toml`.
2. `uv lock --check` + `uv audit` in generated check scripts.
3. Universal hygiene hooks in generated `.pre-commit-config.yaml`.
4. CI hardening of generated `.github/workflows/ci.yml`.
5. Generated `.github/dependabot.yml`.
6. New generated files: `SECURITY.md`,
   `.github/PULL_REQUEST_TEMPLATE.md`, `.git-blame-ignore-revs`,
   `.vscode/settings.json`, `.vscode/extensions.json`.
7. Scaffolder flags `--no-security` / `-NoSecurity` and
   `--no-vscode` / `-NoVscode`.
8. Test updates in all four existing test scripts.
9. RepoSeed README + CHANGELOG updates.

Non-goals (deferred to cycles 2 and 3):

- Any frontend tooling change (Biome/Prettier, jsx-a11y, axe, size budgets,
  tsconfig strictness, `npm audit`).
- Scaffolder-itself linting (shellcheck / PSScriptAnalyzer), mutation testing.
- Stricter opt-in ruff (`N`, `COM`, preview rules) — the `--strict` idea.
- Release tooling, devcontainers, CODEOWNERS, issue templates, docs skeleton.
- Changing `fix.*` scripts in any way.

## Current behavior (repository anchors)

Validated by reading both scaffolders end to end:

| Artifact | Bash (`new-project.sh`) | PowerShell (`new-project.ps1`) |
|---|---|---|
| base ruff config | 228–293 (commented select at 235–247) | 1158–1223 (base+desktop) |
| web/game ruff config | 568–621 | 245–296 |
| base check script | 383–389 | 1353–1373 (base+desktop) |
| game check script | 494–509 | 703–742 |
| web check script | 529–544 | 745–784 |
| base fix script | 391–398 | 1375–1396 |
| game/web fix scripts | 511–527 / 546–562 | 788–828 / 831–871 |
| pre-commit (web/game) | 1189–1197 | 915–925 |
| pre-commit (base) | 1234–1263 | 1318–1349 (base+desktop) |
| CI base | 886–924 | 1452–1488 (base+desktop) |
| CI game | 930–1003 | 931–1006 |
| CI web | 1005–1071 | 1009–1077 |
| .gitignore w/ `.vscode/` | 373 (base), 483 (web/game) | 1308 (base), 690 (web/game) |
| flag parsing | 24–26 init, 146–190 parse, usage 28–44 | param block 1–15 |
| README (generated) | 1158–1178 (web), 1266–1283 (base) | 876–898 (web), 1414–1432 (base) |

Current CI uses `actions/checkout@v6`, `astral-sh/setup-uv@v8.2.0`,
`actions/setup-node@v6` (web/game), all tag-pinned. Current pre-commit config
is `repo: local` only.

## Design decisions (all resolved)

### D1 — Ruff rules added, default-on

`select` gains `"S"`, `"PIE"`, `"TC"`, `"T10"`, `"ERA"` after the existing
entries. Prefixes verified against current ruff docs: flake8-bandit is `S`,
flake8-type-checking is `TC` (renamed from `TCH`), debugger is `T10`,
eradicate is `ERA`, flake8-pie is `PIE`. All stable, none preview.

Because generated tests use `assert` (S101), every generated pyproject also
gains:

```toml
[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]
```

The pattern is relative to each pyproject, so it covers `tests/` (base,
desktop) and `backend/tests/` (web, game) without change.

`[tool.ruff.format]` gains `docstring-code-format = true`.

Base profile keeps its commented style; web/game keep the single-line style,
extended in place.

### D2 — Check scripts gain lock + audit, fix scripts unchanged

`uv lock --check` and `uv audit` are prepended to the Python block of every
generated `check.sh` / `check.ps1` (before any `uv run`, because `uv run`
auto-re-locks and would mask a stale lockfile). `fix.*` scripts are unchanged:
audit failures are not auto-fixable, and `check` remains the gate. Order:

```
uv lock --check
uv audit
uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pytest
```

(web/game: the two lines go inside the `backend` block, before the existing
`uv run` lines.)

`--no-security` / `-NoSecurity` omits exactly these two lines from the check
scripts and nothing else. CI hardening, Dependabot, hooks, and ruff rules are
always generated (CI is always online; the flag exists for offline local
workflows where `uv audit` cannot reach the advisory database).

### D3 — Pre-commit: hygiene hooks only (deviation from brainstorm)

The brainstorm proposed gitleaks + actionlint as pre-commit hooks. Verified
against their `.pre-commit-hooks.yaml`: both default to `language: golang`
(docker variants require Docker). Python users rarely have Go, so those hooks
would break `pre-commit install` out of the box. Deviation, per intent
preserved:

- gitleaks runs in CI only (D4); locally `detect-private-key` catches obvious
  key material with zero dependencies.
- actionlint runs in CI only (D4).

Every generated `.pre-commit-config.yaml` keeps its existing `repo: local`
block verbatim and gains, before it:

```yaml
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: mixed-line-ending
      - id: detect-private-key
      - id: check-merge-conflict
      - id: check-case-conflict
```

All are `language: python` (managed by pre-commit itself, no Go/Docker).
`end-of-file-fixer` and `trailing-whitespace` auto-fix; generated content
already complies (`.editorconfig` mandates the same rules), and the first
auto-fix on a stray file is desired behavior.

### D4 — CI hardening (all six CI generation sites)

Every generated `ci.yml`:

1. Pins all `uses:` by commit SHA with a version comment:

   | Action | Pin | Comment |
   |---|---|---|
   | actions/checkout | `d23441a48e516b6c34aea4fa41551a30e30af803` | v6.1.0 |
   | astral-sh/setup-uv | `fac544c07dec837d0ccb6301d7b5580bf5edae39` | v8.2.0 |
   | actions/setup-node | `249970729cb0ef3589644e2896645e5dc5ba9c38` | v6.5.0 |
   | step-security/harden-runner | `b09bb98e06d4d774595224525879c09bc6e98c40` | v2.20.1 |
   | gitleaks/gitleaks-action | `ff98106e4c7b2bc287b24eaf42907196329070c7` | v2.3.9 |

   SHAs resolved via `git ls-remote` during planning (all tags are
   lightweight; SHA is the commit). Dependabot keeps them current.

2. Gains a concurrency block directly after `on:`:

   ```yaml
   concurrency:
     group: ${{ github.workflow }}-${{ github.ref }}
     cancel-in-progress: true
   ```

3. Runs `step-security/harden-runner` (monitor mode — no egress policy, so it
   cannot break the Playwright browser download) as the first step of every
   job. Monitor mode gives an audit trail of outbound traffic.

4. Adds an actionlint step (first after harden-runner + checkout):

   ```yaml
       - name: Lint workflow files
         run: |
           bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash)
           ./actionlint
   ```

   The download script is pinned to the `v1.7.12` tag.

5. Adds a dependency-audit step after dependency sync:

   ```yaml
       - name: Dependency audit
         run: uv audit
   ```
   (web/game: `working-directory: backend`.)

6. Gains a second job:

   ```yaml
     gitleaks:
       runs-on: ubuntu-latest
       steps:
         - uses: step-security/harden-runner@b09bb98e06d4d774595224525879c09bc6e98c40 # v2.20.1
         - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
           with:
             fetch-depth: 0
         - uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9
           env:
             GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

   `fetch-depth: 0` scans full history. Free for personal accounts;
   organizations request a free license key from gitleaks — noted in the
   generated project README's security line? No: noted in RepoSeed's own
   README only, to keep generated READMEs lean.

CI hardening is NOT gated by `--no-security` (see D2 rationale).

### D5 — Dependabot

Generated `.github/dependabot.yml` (skipped when `--no-github-actions` /
`-NoGitHubActions` is set, alongside the CI workflow):

base/desktop:

```yaml
version: 2
updates:
  - package-ecosystem: uv
    directory: /
    schedule:
      interval: weekly
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

web/game add:

```yaml
  - package-ecosystem: npm
    directory: /frontend
    schedule:
      interval: weekly
```

`uv` is a supported Dependabot ecosystem. `github-actions` updates also
maintain the SHA pins from D4.

### D6 — New generated files

`SECURITY.md`:

```markdown
# Security Policy

## Reporting a Vulnerability

Report security issues privately to the repository maintainer.
Please do not open public issues for security problems.
```

`.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Summary

<!-- What changed and why -->

## Checks

- [ ] `./scripts/check.sh` passes (or `.\scripts\check.ps1` on Windows)
```

`.git-blame-ignore-revs`:

```text
# Commits excluded from `git blame` (e.g. bulk formatting commits).
# Enable with: git config blame.ignoreRevsFile .git-blame-ignore-revs
```

`.vscode/settings.json` (all profiles):

```json
{
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  }
}
```

`.vscode/extensions.json`:

- base/desktop: `["ms-python.python", "charliermarsh.ruff"]`
- web/game: `["ms-python.python", "charliermarsh.ruff", "dbaeumer.vscode-eslint"]`

Deliberately minimal: Ruff format-on-save parity with the CLI; no Pylance
typeCheckingMode override (the pyright CLI gate already enforces types).

`.gitignore` in every profile changes `.vscode/` to:

```text
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
```

so the two shared files are tracked while local editor state stays ignored.

`--no-vscode` / `-NoVscode` skips only the two `.vscode` files (the
`.gitignore` pattern is written regardless; it is inert without the files).

SECURITY.md, PR template, and `.git-blame-ignore-revs` are always generated.

### D7 — New flags

- `--no-security` / `-NoSecurity`: default off. Omits `uv lock --check` and
  `uv audit` from generated check scripts (D2). Bash usage text gains one line
  per flag; PowerShell has no usage text (comment-based help only), matching
  existing flags' treatment.

### D8 — Testing strategy

Behavior is verified at three levels, all in existing harnesses:

| Behavior | Proof |
|---|---|
| New ruff rules pass on generated code | `scaffold_e2e.sh` + `scaffold_e2e.ps1` run real `ruff check` on generated projects |
| `uv lock --check` + `uv audit` actually run and pass on fresh scaffolds | same e2e suites run real `check.*` end to end |
| Ruff config content (S/PIE/TC/T10/ERA, S101 ignore, docstring-code-format) | `cross_platform_contract.sh` (bash) + `powershell_web_contract.ps1` (ps1) content assertions |
| check scripts contain the two lines (and omit them with `--no-security`) | `cross_platform_contract.sh` + `powershell_web_contract.ps1` |
| pre-commit hygiene block present | same two contract tests |
| CI content (SHA pins, concurrency, harden-runner, actionlint, audit, gitleaks job) | `cross_platform_contract.sh` (new: generate WITH GitHub Actions using fake uv, assert ci.yml) + `scaffold_e2e.ps1` / `powershell_web_contract.ps1` CI assertions |
| Dependabot content incl. npm entry for web/game | same |
| New files exist (SECURITY.md, PR template, blame-ignore, .vscode) | contract tests |
| `--no-security` / `--no-vscode` flag behavior | contract tests scaffold twice, with and without |

No new test files are created; the four existing scripts are extended.

## Error handling and edge cases

- **Offline `uv audit`**: fails loudly with a network error. That is the
  designed behavior; `--no-security` exists for offline workflows.
- **`uv audit` version requirement**: `uv audit` shipped in recent uv
  releases; RepoSeed already targets current uv (README requires installing
  uv from astral.sh). Not a compatibility break; noted in CHANGELOG.
- **Stale lockfile**: `uv lock --check` fails before `uv run` can silently
  re-lock — the ordering in D2 is load-bearing and asserted in tests by
  position (lock-check appears before the first `uv run`).
- **gitleaks-action licensing**: free for personal accounts; orgs need a
  free license key. Documented in RepoSeed README (generated projects stay
  lean).
- **harden-runner**: monitor mode cannot block anything, so Playwright's
  browser download and npm registry access are safe.
- **Hygiene hooks first run**: may auto-fix stray whitespace in user files;
  generated files already comply with `.editorconfig` rules. E2E keeps
  `--no-install-hooks`, so upstream hook behavior is trusted and only config
  content is asserted.
- **Fake-uv contract tests**: scaffolding never *executes* `uv audit`, so the
  fake `uv` shims in `cross_platform_contract.sh` / `powershell_web_contract.ps1`
  need no changes.

## Compatibility

- All existing flags and defaults unchanged; new flags default off.
- Generated project layout unchanged apart from added files.
- `fix.*` scripts byte-identical to before.
- Existing test assertions remain true (web/game pre-commit still contains the
  `project-check` entry the tests assert on; CI still contains the frontend
  step names asserted today).
- RepoSeed's own README/CHANGELOG updated to describe new generated content
  and flags.

## Acceptance criteria

```gherkin
Scenario: Ruff config includes new rules (base)
  Given the bash scaffolder runs with profile base
  Then generated pyproject.toml select contains S, PIE, TC, T10, ERA
  And contains per-file-ignores "tests/**" = ["S101"]
  And [tool.ruff.format] contains docstring-code-format = true

Scenario: Ruff config includes new rules (web/game, both platforms)
  Given either scaffolder runs with profile web or game
  Then backend/pyproject.toml matches the same three conditions

Scenario: New ruff rules pass on generated code
  When the e2e suites run the generated check scripts with real uv
  Then ruff check passes with zero violations

Scenario: Check scripts audit dependencies
  Given any profile on either platform without --no-security
  Then check.sh/check.ps1 contains "uv lock --check" and "uv audit"
  And both appear before the first "uv run" in the Python block

Scenario: --no-security omits only the audit lines
  Given any profile with --no-security / -NoSecurity
  Then check scripts omit "uv lock --check" and "uv audit"
  And CI, Dependabot, pre-commit config, and ruff config are unchanged

Scenario: fix scripts unchanged
  Then fix.sh and fix.ps1 contain no uv audit or uv lock --check lines

Scenario: Pre-commit hygiene hooks
  Given any profile on either platform
  Then .pre-commit-config.yaml contains the pre-commit-hooks repo at rev v6.0.0
  With ids check-yaml, check-json, check-toml, end-of-file-fixer,
  trailing-whitespace, mixed-line-ending, detect-private-key,
  check-merge-conflict, check-case-conflict
  And the pre-existing repo: local block is unchanged

Scenario: CI actions are SHA-pinned
  Given any profile with GitHub Actions enabled
  Then every uses: in ci.yml pins a full 40-char SHA with a version comment
  And no uses: pins a bare tag

Scenario: CI has concurrency, harden-runner, actionlint, audit, gitleaks
  Given any profile with GitHub Actions enabled
  Then ci.yml contains the concurrency block with cancel-in-progress
  And a harden-runner step in every job
  And a workflow lint step invoking actionlint's pinned download script
  And a "Dependency audit" step running uv audit
  And a gitleaks job with fetch-depth: 0 and GITHUB_TOKEN

Scenario: Dependabot config
  Given base or desktop with GitHub Actions enabled
  Then .github/dependabot.yml covers uv and github-actions weekly
  Given web or game
  Then it also covers npm at /frontend

Scenario: Dependabot skipped with --no-github-actions
  Given --no-github-actions / -NoGitHubActions
  Then .github/dependabot.yml and ci.yml are not written

Scenario: New repo files exist
  Given any profile on either platform
  Then SECURITY.md, .github/PULL_REQUEST_TEMPLATE.md, .git-blame-ignore-revs
  And .vscode/settings.json and .vscode/extensions.json exist
  And .gitignore contains the .vscode/* negation pattern

Scenario: --no-vscode skips editor files
  Given --no-vscode / -NoVscode
  Then .vscode/ files are absent and all other new files still exist

Scenario: Full pipeline stays green
  When scaffold_e2e.sh, scaffold_e2e.ps1, cross_platform_contract.sh, and
  powershell_web_contract.ps1 all run
  Then all pass, including real uv lock --check and uv audit on fresh projects
```

## Mechanical assumptions

- Dependabot's `uv` ecosystem remains available on GitHub (it is today).
- Tag SHAs listed in D4 are current as of planning; the implementation uses
  exactly these values (updating them later is Dependabot's job in generated
  projects, and a manual bump in RepoSeed).

## Deferred

- Cycle 2: frontend tooling overhaul.
- Cycle 3: scaffolder-itself quality (shellcheck, PSScriptAnalyzer).
- `--strict` ruff/pyright mode; CODEOWNERS; issue templates; docs skeleton.

## Plain-language summary

Projects made with RepoSeed will now check their dependencies for known
security holes every time checks run, keep the lockfile honest, keep secrets
out of git history (CI scanner plus local key detection), follow five extra
well-vetted lint rule families, and their CI will be both harder to attack
(pinned action versions, monitored network traffic) and better maintained
(weekly dependency-update PRs). New opt-out flags keep offline and
non-VS-Code workflows comfortable. The fix scripts and every existing command
stay exactly as they were.
