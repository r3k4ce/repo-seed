# AGENTS.md

## Project

* Python project managed with `uv`.
* Source: `src/__PACKAGE_NAME__/`
* Tests: `tests/`
* Windows/PowerShell-first. Prefer repo scripts over ad hoc commands.

## Authority

Follow this order:

1. User task.
2. This `AGENTS.md`.
3. Existing code, tests, docs, and project patterns.
4. Available skills/tools.

If instructions conflict, preserve user intent and existing behavior. Ask only when the conflict affects behavior, data, security, architecture, dependencies, UX, or workflow.

## Skills

Use available skills without bloating the response.

* **Superpowers**: use for non-trivial features, bugs, refactors, plans, and reviews.
* **Ponytail**: use by default to minimize code, avoid speculative abstractions, prefer deletion, stdlib, existing helpers, and existing patterns.
* **Context7**: use when current library, SDK, framework, CI, auth, deployment, API, or security docs matter.

If a skill/tool is unavailable, continue with the closest local workflow. Do not spend tokens explaining tool availability unless it changes the result.

## Core Rules

* Keep changes small, test-first, and evidence-based.
* Preserve existing behavior unless the task explicitly changes it.
* Do not add broad refactors, new architecture, speculative abstractions, alternate implementations, or future configurability.
* Prefer stdlib and existing project helpers before adding dependencies.
* Keep validation, security, data safety, accessibility, and tests intact.
* Preserve unrelated user changes. Stop if local changes conflict with the task.

## Decision Questions

Ask focused questions only when the answer affects behavior, UX, architecture, dependencies, workflow, data, security, or user expectations.

When asking:

* Ask 1–3 questions max.
* Use beginner-friendly language.
* Explain why the choice matters in one short sentence.
* Give concrete options.
* Recommend a default.

Do not ask about small reversible code mechanics. Choose the simplest option and record the assumption in the handoff.

## Research

* Inspect local files first.
* Use `rg`, `fd`, `jq`, and `yq` when available; otherwise use PowerShell or Python stdlib.
* Use Context7 before relying on current external library/API/framework docs.
* Use web/docs research only when current external facts matter or the user asks.
* Summarize findings. Do not paste long docs, logs, or unrelated search results.

## Workflow

1. Inspect relevant files.
2. Clarify only blocking decisions.
3. For behavior changes and bug fixes, write or update a focused failing test first when practical.
4. Implement the smallest correct change.
5. Run the focused check first.
6. Run `.\scripts\check.ps1` when feasible.
7. Update docs memory only when required.
8. Hand off compactly.

Docs, comments, and simple config-only edits may skip the red test step.

## Commands

```powershell
uv sync --dev
uv run pytest
uv run pyright
uv run ruff check .
uv run ruff format --check .
.\scripts\check.ps1
.\scripts\fix.ps1
```

Use `uv add` or `uv add --dev` for dependencies.

## Security

* Never commit secrets.
* Do not create `.env`.
* Update `.env.example` with placeholder names when new environment variables are required.
* Keep real secret values out of the repo.

## Git

* Do not stage or commit.
* Do not run `git add`, `git commit`, or equivalent commands.
* Read-only Git inspection is allowed: `git status`, `git diff`, `git log`.

## Docs Memory

Update `docs/project-memory.yaml` only when completed work changes code, behavior, dependencies, workflow, structure, or important decisions.

Keep entries compact and machine-readable:

```yaml
time_utc:
time_local:
summary:
changed:
verification:
```

Do not record proposed work, suggested commit messages, or follow-ups. If no memory update is needed, say why in the handoff.

## Handoff

Keep the final handoff compact. Include only relevant sections:

* Changed: behavior and files touched.
* Verified: commands run and results.
* Skipped: checks not run and why.
* Docs: memory update or why none was needed.
* Risks: remaining issues or assumptions.
* Commit: suggested Conventional Commit message.

Prefer 12 lines or fewer. Expand only when failures, risks, migrations, or user decisions require it.
