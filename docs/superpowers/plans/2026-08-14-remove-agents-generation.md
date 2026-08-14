# Implementation Plan: Remove AGENTS.md generation from all profiles

Date: 2026-08-14
Spec: docs/superpowers/specs/2026-08-14-remove-agents-generation-design.md

## Repository context

- Branch: `main` (upstream: `scaffold_script/main`), HEAD `3baf421` at planning time.
- No feature branch; per user-managed-branch rules all work stays on `main`.
- Known baseline noise: modified `.superpowers/sdd/progress.md` and untracked
  `.superpowers/sdd/*` files from the previous cycle. Left untouched.
- No canonical wrapper script exists; the fast verification set is
  `tests/cross_platform_contract.sh` (run via WSL bash) and
  `tests/powershell_web_contract.ps1` (run via Windows PowerShell).

## File map

| File | Change |
|---|---|
| `new-project.sh` | Delete `write_agents_file` (138-145), its two calls (1202, 1308), header comment lines 5-8, and `AGENTS.md, ` in memory strings (1115, 1126, 1304) |
| `new-project.ps1` | Delete `Write-AgentsFile` (140-147), its two calls (924, 1460), and `AGENTS.md, ` in memory strings (220 both branches, 1455) |
| `templates/agents/**` (5 files) | Delete directory |
| `tests/cross_platform_contract.sh` | `run_agents_contract` -> absence assertion; PowerShell section: drop content assertions, add absence assertion |
| `tests/powershell_web_contract.ps1` | Add AGENTS.md absence check after scaffold |
| `tests/scaffold_e2e.sh` | Add AGENTS.md absence check in `run_scaffold_case` (covers base/web/game when e2e runs) |
| `tests/scaffold_e2e.ps1` | Add AGENTS.md absence check after scaffold (covers web when e2e runs) |
| `README.md` | Remove AGENTS.md mentions (lines 12, 22, 30-31, 33, 57, 137, 331-332, 349-350, 368-369, 390-391); fix tree last-entry markers |
| `CHANGELOG.md` | Add Unreleased `### Removed` entry |

No other files reference AGENTS.md generation (validated by search).

## Task 1 — Remove generation, tests first

Feature goal: no scaffolder generates AGENTS.md for any profile.
Previously: verified baseline `3baf421` plus the planning-artifact commit;
scaffolders generate AGENTS.md via template composition.
Current: delete generation end-to-end (both scaffolders, templates, memory
strings) with contract tests flipped to assert absence.
Next: Task 2 updates RepoSeed's own README/CHANGELOG text only.
Do not do yet: any README/CHANGELOG edits (Task 2), installer changes (none needed).

Steps (red-green):

1. Edit `tests/cross_platform_contract.sh`:
   - Rename `run_agents_contract` to `run_base_scaffold_contract` (update the
     call at line 187). Keep the fake-uv base-profile scaffold run.
   - Replace its five content assertions (lines 138-143) with:
     `if [[ -e "$agents_path" ]]; then printf 'Expected no AGENTS.md: %s\n' ...; exit 1; fi`
   - In `run_powershell_contract_if_available`, delete lines 179-182 and add
     the same `-e "$project_dir/AGENTS.md"` absence check.
2. Edit `tests/powershell_web_contract.ps1`: after the scaffold block, add
   `if (Test-Path -LiteralPath (Join-Path $ProjectDir "AGENTS.md")) { throw ... }`.
   Edit `tests/scaffold_e2e.sh` `run_scaffold_case` and
   `tests/scaffold_e2e.ps1` (after scaffold): same one-line absence checks.
   These e2e checks are exercised only when the heavy e2e runs; they are not
   part of the fast red/green gate.
3. RED: run both fast tests; expected failure = AGENTS.md still generated.
   - `powershell -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1`
   - `bash -c "cd /mnt/c/Users/Usuario/Documents/Development/repoSeed && bash tests/cross_platform_contract.sh"`
     (PowerShell section auto-skips in WSL; Bash absence assert provides red)
4. Edit `new-project.sh`: remove header comment lines 5-8, `write_agents_file`,
   calls at 1202 and 1308, and `, AGENTS.md` from the three memory strings
   (e.g. `...checks, CI, hooks, and memory file.`).
5. Edit `new-project.ps1`: remove `Write-AgentsFile`, calls at 924 and 1460,
   and `, AGENTS.md` from memory strings at 220 (both branches) and 1455.
6. `git rm -r templates/agents` (5 files).
7. GREEN: rerun both fast tests; both pass.
8. Static: `rg -n "AGENTS|agents/" new-project.sh new-project.ps1 tests/` ->
   only the new absence checks match.

Task Boundary Verification:

- Focused: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1` -> exit 0, "PowerShell web contract passed"
- `bash -c "cd /mnt/c/.../repoSeed && bash tests/cross_platform_contract.sh"` -> exit 0, "cross-platform contract tests passed"
- Regression search `rg -n "AGENTS" new-project.sh new-project.ps1 templates/` -> no matches
- `git status` shows templates/agents deletions plus intended edits only
- Expected known failures: none
- Next task may assume: no generator or template produces/references AGENTS.md

## Task 2 — Documentation and changelog

Feature goal: same as Task 1.
Previously: Task 1 removed generation; tests prove absence.
Current: RepoSeed's docs stop claiming AGENTS.md generation.
Next: final whole-branch verification (all fast tests + search).
Do not do yet: anything else.

Steps:

1. `README.md`:
   - Line 12: "It creates the folder layout, config files, tests, and
     scripts, then sets up git, hooks, and a GitHub Actions workflow...".
   - Line 22: "same four problems" -> "same three problems"; delete bullet
     lines 30-31 ("Weak agent instructions"); line 33 "fixes all four" ->
     "fixes all three".
   - Delete "What it creates" bullet line 57.
   - Demo tree: delete line 137.
   - Profile trees: delete the AGENTS.md line and promote the preceding entry
     to the `` `-- `` marker: base (331-332), desktop (349-350),
     web (368-369), game (390-391).
2. `CHANGELOG.md`: under `[Unreleased]`, after the existing `### Changed`,
   add:
   `### Removed` -> "- Scaffolders no longer generate `AGENTS.md` in new projects; the `templates/agents/` templates were removed."
3. Verify: `rg -n "AGENTS" README.md CHANGELOG.md` -> only the Unreleased
   Removed entry and the untouched v0.1.0 history.
4. Rerun both fast tests (cheap; confirms docs-only task left behavior green).

Task Boundary Verification:

- `rg -n "AGENTS" README.md CHANGELOG.md` -> historical + Unreleased only
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests\powershell_web_contract.ps1` -> exit 0
- Bash contract test -> exit 0
- Expected known failures: none

## Exclusions

- No installer edits; no e2e test changes; no generated-project README
  template changes; no replacement for AGENTS.md; heavy e2e runs optional.
