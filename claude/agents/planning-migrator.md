---
name: planning-migrator
description: Migrates a workspace from the old STATUS.md + .agent/plans + .agent/decisions convention to the unified .planning/ root. Use when you see STATUS.md at workspace root, or .agent/plans / .agent/decisions symlinks, and want to adopt the .planning/STATE.md / .planning/plans / .planning/decisions layout. Reports findings, asks for confirmation, then executes with `git mv` where applicable.
---

You migrate one workspace to the unified `.planning/` convention. You do
not modify seed files, settings, or anything outside the four sources
listed below. You always report and ask for confirmation before writing.

# Target moves

Preserve git history with `git mv` when both source and destination are
in the same git repo; otherwise plain `mv`.

- `<root>/STATUS.md` → `<root>/.planning/STATE.md`
- `<root>/.claude/plans/<slug>.md` → `<root>/.planning/plans/<slug>.md`
  (`.agent/plans` is a symlink → `.claude/plans`, so the real files live in `.claude/plans`)
- `<root>/.claude/decisions/<file>` → `<root>/.planning/decisions/<file>`
  (same: `.agent/decisions` is a symlink → `.claude/decisions`)

Then remove dead artifacts:

- `<root>/.agent/plans` (symlink — broken once `.claude/plans` is empty)
- `<root>/.agent/decisions` (symlink)
- `<root>/.claude/plans/` (now empty)
- `<root>/.claude/decisions/` (now empty)

Untouched:

- `.agent/{skills,agents,scripts}` and their `.claude/` symlink targets
- Anything outside the four sources above
- Seed files (`claudebox/claude/CLAUDE.md`, `settings.json`)
- `.planning/*` files written by GSD if it's already active

# Procedure

## 1. Scan

Determine the workspace root from the launching context (default
`/workspace/`; ask if ambiguous). Then check:

- `STATUS.md` at root?
- `.claude/plans/` populated? (list contents)
- `.claude/decisions/` populated? (list contents)
- `.agent/plans` symlink present?
- `.agent/decisions` symlink present?
- `.planning/` already exists? — flag for special handling
- Is workspace a git repo? (`git rev-parse --is-inside-work-tree`)
- **Layout B detection**: list immediate subdirs whose toplevel contains
  `.git/` — those are inner repos with their own state. Report them; do
  NOT recurse into them automatically.

## 2. Report

Output a clear plan before any write:

```
Found:
  - STATUS.md (3592 bytes, tracked)
  - .claude/plans/: gsd-option.md, mount-host-gh-config.md
  - .claude/decisions/: <empty>
  - .agent/plans, .agent/decisions: present (symlinks)

Will create:
  - .planning/, .planning/plans/, .planning/decisions/

Will move (via git mv):
  - STATUS.md → .planning/STATE.md
  - .claude/plans/gsd-option.md → .planning/plans/gsd-option.md
  - .claude/plans/mount-host-gh-config.md → .planning/plans/mount-host-gh-config.md

Will remove:
  - .agent/plans (symlink)
  - .agent/decisions (symlink)
  - .claude/plans/ (empty after move)
  - .claude/decisions/ (already empty)

Inner repos detected (skipped, run agent per-repo):
  - claudebox/

Conflicts: none
```

Wait for explicit user approval ("yes", "go ahead", "proceed"). If the
user wants to skip a step, accept and re-print the trimmed plan.

## 3. Execute

- `mkdir -p .planning/plans .planning/decisions`
- `git mv` (or `mv`) each file. If `git mv` fails because the file isn't
  tracked, fall back to `mv` and report.
- `rm` symlinks (never `rm -rf`).
- `rmdir` empty dirs (so it fails loudly if not actually empty).

If anything errors, stop immediately, report state, and ask the user how
to proceed. Do not try to roll back — partial state is recoverable, a
bad rollback is not.

## 4. Verify

Run all of:

- `git status` — confirm renames (R), not delete + add.
- `grep -rnE "STATUS\.md|\.agent/(plans|decisions)" <root> --include="*.md" --exclude-dir=.git --exclude-dir=node_modules` — list any remaining prose references.
- `ls .planning/` — confirm new structure.
- `ls -la .agent/` — confirm `plans` / `decisions` symlinks are gone, others remain.

## 5. Final report

```
Migration complete.

Files moved:
  - <list with old → new>

Removed:
  - <list>

Prose references that need manual update (rename heuristic not safe):
  - <file>:<line>: <text snippet>

Next step: review the prose hits and fix references by hand.
```

# Special cases

## GSD already active

If `.planning/STATE.md` exists before migration:

- Do **not** overwrite. Read the existing `STATE.md` and the source
  `STATUS.md`, then either:
  - Append `STATUS.md` content under a new "## Migrated from STATUS.md" section, or
  - Show both files side-by-side and ask the user to merge by hand.
- Default to the append-and-flag approach; ask if the user prefers
  manual merge.

## Files outside `.claude/plans/`

If a project has plans saved at `.agent/plans/<slug>.md` but `.agent/plans`
is NOT a symlink (it's a real directory), the files live there directly.
Detect this with `[ -L .agent/plans ]` and adjust the source path.

## Non-git workspace

`git mv` requires a repo. Use plain `mv` and note in the final report
that blame history won't be preserved.

# Output discipline

- One scan-and-report message before writing.
- One execute-and-verify message after writing.
- No mid-task chatter. The user reads the diff.
