---
name: migrate-to-planning
description: When a workspace still uses the old project-state layout (STATUS.md at root, .agent/plans/, .agent/decisions/), migrate it to the unified .planning/ convention (.planning/STATE.md, .planning/plans/<slug>.md, .planning/decisions/NNN-<slug>.md). Triggers when you see STATUS.md at workspace root, or .agent/plans / .agent/decisions symlinks. Delegates the actual file moves to the planning-migrator subagent.
---

# Migrate workspace to .planning/ convention

## Why this exists

The original convention split project state across three roots:

- `/workspace/STATUS.md` — heartbeat
- `/workspace/.agent/plans/<slug>.md` — task plans
- `/workspace/.agent/decisions/NNN-<slug>.md` — ADRs

It was unified into a single `.planning/` root so opting into the
[GSD (Get Shit Done)](https://github.com/gsd-build/get-shit-done) workflow
doesn't fork the state model. GSD writes its own files at `.planning/`
root (`STATE.md`, `{N}-PLAN.md`, …); our subdirs (`.planning/plans/`,
`.planning/decisions/`) live alongside without collision.

Target layout:

| Before | After |
|---|---|
| `STATUS.md` | `.planning/STATE.md` |
| `.agent/plans/<slug>.md` | `.planning/plans/<slug>.md` |
| `.agent/decisions/NNN-<slug>.md` | `.planning/decisions/NNN-<slug>.md` |

`.agent/{skills,agents,scripts}` stays — those still need the `.claude/`
symlink trick to bypass the harness write-prompt carve-out.
`.agent/plans` and `.agent/decisions` symlinks become dead and are removed.

## How to use

Launch the `planning-migrator` subagent. It scans, reports, asks for
confirmation, then executes. Don't run the moves yourself — the
report-then-confirm step matters.

```
Use the planning-migrator agent to migrate this workspace.
```

## Edge cases the agent handles, but you should sanity-check

- **GSD already active** (`.planning/STATE.md` already exists). The agent
  must not overwrite — it appends the contents of `STATUS.md` under a new
  section in the existing `STATE.md` and asks the user to reconcile.
- **Inner repos (Layout B)**. Each inner repo at `/workspace/<project>/`
  may have its own state. Run the agent in each inner repo separately;
  outer (agent-state) repo is usually where `.agent/` symlinks live.
- **Prose references**. CLAUDE.md, README.md, or `.planning/*.md` files
  may mention the old paths. The agent greps for them and surfaces hits;
  fix the prose by hand (rename heuristic isn't safe to automate).
- **Uncommitted changes to STATUS.md**. The agent uses `git mv` to
  preserve blame. If the move conflicts with an in-progress edit, it
  stops and asks.
- **No STATUS.md / no `.agent/plans`**. Project may already be migrated,
  or never used the convention. The agent reports "nothing to do" and exits.

## Verification after the agent finishes

- `git status` shows renames (R), not delete + add.
- `grep -rE "STATUS\.md|\.agent/(plans|decisions)" --include="*.md"` returns
  no hits in prose docs.
- `ls .planning/` shows `STATE.md`, `plans/`, `decisions/`.
- `.agent/plans` and `.agent/decisions` are gone; `.agent/skills`,
  `.agent/agents`, `.agent/scripts` are untouched.

## Companion

- Subagent that does the work: `planning-migrator`
- Convention doc this should stay in sync with: `claudebox/claude/CLAUDE.md`
  "Plans & project status" section.

## Promoting this skill cross-project

This skill currently lives in workspace-scope (`.agent/skills/`). Once
it's been used on at least one other project successfully, move (or copy)
it to `~/.claude/skills/migrate-to-planning/` to make it available in
every container.
