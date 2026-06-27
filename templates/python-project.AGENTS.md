# AGENTS.md

## Project Context

Source code lives in `src/__PACKAGE_NAME__/`. Tests live in `tests/`.

## Core Rules

- Use `uv`.
- Keep changes small, test-first, and evidence-based.
- Make the smallest practical change. Avoid broad refactors, extra dependencies, and new architecture unless the task calls for them.

## Workflow

- Inspect relevant files before editing. Preserve unrelated user changes and stop if they conflict with the task.
- For behavior changes and bug fixes, write or update a focused test first and run it before editing. Docs, comments, and simple config-only edits may skip the red step.
- Inspect local files first. Use Context7 or web search only when current external facts matter, such as SDKs, documentation, CI actions, auth, deployment, or security-sensitive behavior.
- Ask before editing when a decision affects behavior, UX, architecture, dependencies, workflow, data, or user expectations. For small local code mechanics, choose the simplest reversible option and mention the assumption in the handoff.

## Testing and Verification

- Verify with the focused test first, then run `.\scripts\check.ps1` when feasible. If a check cannot run, report why.

## Dependencies and Security

- Use `uv add` or `uv add --dev` for dependencies. Store API keys and other secrets in `.env`, but never create `.env`; create or update `.env.example` with placeholder names instead. Keep real secret values out of the repo.

## Git Boundaries

- Do not stage or commit changes. Do not run `git add`, `git commit`, or equivalent staging/commit commands.
- Read-only Git inspection is allowed, such as `git status` and `git diff`.
- After the work is done, suggest a Conventional Commit message, but leave staging and committing to the user.

## Communication

- Keep the user on the same page. Before asking for a decision, briefly explain why the choice matters and what would change.
- Ask focused questions, not broad open-ended ones. Offer concrete options when that makes the tradeoff clearer.
- Teach as you go when it affects a decision or handoff. Define important code, tooling, or workflow terms in plain English before relying on them.
- Keep explanations practical and concise. Do not turn routine updates into long tutorials unless the user asks for more depth.
- In final handoffs, be clear, beginner-friendly, and technically accurate.

## Docs

- Keep `docs/project-log.md` current when code, behavior, dependencies, workflow, structure, or important decisions change.
- If no docs update is needed, say why in the final handoff. Keep entries compact and useful to the next developer.

## Commands

```powershell
uv sync --dev
uv run pytest
uv run pyright
uv run ruff check .
.\scripts\check.ps1
```

## Handoff

Report changed behavior, files touched, verification commands/results, skipped checks, remaining risks,
assumptions made, and a suggested Conventional Commit message. Do not stage or commit the changes.
