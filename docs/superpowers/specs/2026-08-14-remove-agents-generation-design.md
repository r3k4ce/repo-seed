# Spec: Remove AGENTS.md generation from all profiles

Date: 2026-08-14
Status: Approved at Gate 1, awaiting Gate 2

## Problem

Both scaffolders (`new-project.sh` and `new-project.ps1`) generate an
`AGENTS.md` in every new project by combining `templates/agents/base.md` with
a profile snippet from `templates/agents/profiles/`. The user no longer wants
this file generated for any profile.

## Goal and user-visible outcome

New projects scaffolded with any profile (`base`, `desktop`, `web`, `game`)
on either platform (Bash, PowerShell) contain no `AGENTS.md`. Everything else
the scaffolders generate is unchanged. RepoSeed's own docs no longer promise
the file.

## Scope

In scope:

- Remove `AGENTS.md` generation from both scaffolders.
- Delete `templates/agents/` (5 files: `base.md`, `profiles/base.md`,
  `profiles/web.md`, `profiles/game.md`, `profiles/desktop.md`).
- Update generated project-memory `changed:` strings that mention `AGENTS.md`.
- Update contract tests: assert `AGENTS.md` is absent instead of asserting
  its contents.
- Update README and CHANGELOG so live documentation no longer claims the file
  is generated. Historical v0.1.0 CHANGELOG entries stay untouched.

Non-goals:

- No changes to generated application code, checks, CI, hooks, README
  templates of generated projects, or installer behavior (installers copy
  `templates/` wholesale; README already documents that removed templates do
  not linger after reinstall).
- No replacement mechanism (no opt-in flag, no CLAUDE.md/GEMINI.md etc.).
- No edits to previously generated projects.

## Current behavior (validated in repository)

- `new-project.sh:138-145` defines `write_agents_file`; called at lines 1202
  (web/game) and 1308 (base). Header comment lines 5-8 list the agents
  templates. Memory strings at lines 1115, 1126, 1304 mention `AGENTS.md`.
- `new-project.ps1:140-147` defines `Write-AgentsFile`; called at lines 924
  (web/game) and 1460 (base/desktop). Memory strings at lines 220 and 1455
  mention `AGENTS.md`.
- `tests/cross_platform_contract.sh` `run_agents_contract` (lines 121-144)
  asserts Bash-generated `AGENTS.md` contents; the PowerShell section
  (lines 179-182) asserts PowerShell-generated `AGENTS.md` contents.
- `tests/powershell_web_contract.ps1` has no AGENTS assertions today.
- `tests/scaffold_e2e.sh` and `tests/scaffold_e2e.ps1` have no AGENTS
  references.
- README mentions `AGENTS.md` at lines 12, 30-31, 57, 137, 332, 350, 369,
  391 (intro, "Why" bullet, "What it creates" bullet, four profile trees,
  demo tree).
- CHANGELOG v0.1.0 (lines 41-42) mentions AGENTS.md historically.

## Design

Plain deletion, no new abstraction:

1. Both scaffolders lose their agents-file writer function, its call sites,
   the `AGENTS.md, ` phrase in memory strings, and (Bash only) the header
   comment lines naming the agents templates.
2. `templates/agents/` is deleted. Installers need no change.
3. Contract tests flip from content assertions to absence assertions:
   - `cross_platform_contract.sh`: the Bash base-profile scaffold run stays
     (it is the only fast Bash base-profile contract), followed by
     `[[ -e AGENTS.md ]] -> fail`. The PowerShell section drops its content
     assertions and gains the same absence check.
   - `powershell_web_contract.ps1`: gains one absence check after scaffold,
     giving Windows-native coverage without pwsh-in-WSL.
4. README loses every AGENTS.md mention; the "Why" section shrinks from four
   problems to three. CHANGELOG gains an Unreleased "Removed" entry.

## Acceptance criteria

```gherkin
Scenario: Bash base profile
  Given an empty directory with fake uv on PATH
  When new-project.sh runs with default (base) profile
  Then the project contains no AGENTS.md file
  And docs/project-memory.yaml's changed entry does not mention AGENTS.md

Scenario: Bash web and game profiles
  Given an empty directory with uv and npm available
  When new-project.sh runs with --profile web or --profile game
  Then the project contains no AGENTS.md file

Scenario: PowerShell profiles
  Given an empty directory with fake uv (and npm for web) on PATH
  When new-project.ps1 runs with -Profile base, desktop, web, or game
  Then the project contains no AGENTS.md file

Scenario: Templates removed
  When anyone lists templates/
  Then the agents/ directory does not exist
  And no scaffolder code references agents templates

Scenario: Documentation is accurate
  When anyone reads README.md or the CHANGELOG Unreleased section
  Then no live claim says AGENTS.md is generated
  And the historical v0.1.0 CHANGELOG entry is unchanged
```

Desktop-profile absence is covered by code-path unification (the single
`Write-AgentsFile` call at new-project.ps1:1460 serves base and desktop) plus
the PowerShell base/web contract assertions.

## Testing strategy

- Focused fast tests (fake uv/npm, no network): `tests/cross_platform_contract.sh`
  and `tests/powershell_web_contract.ps1`. These are the red/green drivers.
- Heavy e2e (`tests/scaffold_e2e.sh`, `tests/scaffold_e2e.ps1`) contain no
  AGENTS references and are unaffected; run when environment and time permit,
  not a task gate.
- Static check: repository-wide search confirms the only remaining `AGENTS`
  mentions are historical (CHANGELOG v0.1.0) or the new Unreleased entry.

## Mechanical assumptions

- None beyond the scope above. No user decisions remain.
