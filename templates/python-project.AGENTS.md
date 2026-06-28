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
* Prefer editing existing files. Create new files only when needed for tests, packaging, docs policy, or the requested feature.
* Keep validation, security, data safety, accessibility, and tests intact.
* Preserve unrelated user changes. Stop if local changes conflict with the task.
* If the user asks for a plan, review, opinion, or recommendation, stay read-only unless they explicitly ask for implementation.
* Finish the requested outcome end to end, including obvious neighboring files and checks needed for the change to actually work.

## Decision Questions

Ask focused questions before implementation when the goal, success criteria, UX, data shape, behavior boundary, or completion boundary is unclear.

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
2. Clarify scope gaps before implementation.
3. For behavior changes and bug fixes, write or update one focused failing test first unless the change is docs/config-only or no test harness exists.
4. Implement the smallest correct change.
5. Run the focused check first.
6. Run `.\scripts\check.ps1` when feasible.
7. Update affected docs only when behavior, setup, commands, configuration, dependencies, architecture, or workflow changed.
8. Update docs memory only when required.
9. Hand off compactly.

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

## Docs

* Update `README.md` only when setup, commands, usage, config, dependencies, or user-facing behavior changes.
* Update `.env.example` when new env vars are required. Never create `.env`.
* Update `docs/project-memory.yaml` only after completed implementation for code, behavior, dependency, workflow, structure, or decision changes.
* Optional docs: `docs/architecture.md`, `docs/decisions.md`, `docs/troubleshooting.md`, only when they reduce future confusion.
* Do not create docs for obvious code, temporary plans, proposed work, failed attempts, exploratory work, commit messages, or routine details.

Keep `docs/project-memory.yaml` entries compact and machine-readable:

```yaml
time_utc:
time_local:
summary:
changed:
verification:
```

If no docs update is needed, say why in the handoff.

## Handoff

Keep the final handoff compact. Include only relevant sections:

* Changed: behavior and files touched.
* Verified: commands run and results.
* Skipped: checks not run and why.
* Docs: memory update or why none was needed.
* Commit: suggested Conventional Commit message.

Prefer 12 lines or fewer. Expand only when failures, risks, migrations, or user decisions require it.
Do not include broad explanations, future feature ideas, or unrelated cleanup suggestions.
