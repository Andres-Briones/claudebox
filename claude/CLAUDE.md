# Global preferences

These are defaults. A project's own CLAUDE.md overrides any rule here when
they conflict.

## Environment
- Tooling available in this container: @~/.claudebox/tooling.md

## Code style
- Match the surrounding code. Don't refactor unrelated things in the same change.
- Comments: only when the *reason* for the code isn't obvious from reading it
  (a workaround, a hidden constraint, a non-obvious invariant). Don't narrate
  what the code does — well-named identifiers already do that.
- Prefer small, reversible changes. Ask before destructive or hard-to-reverse actions.
- Before referencing a path, command, or symbol in docs or comments, verify it exists.
- When a spec is unclear or a change has multiple reasonable interpretations, ask rather than guess.

## Tests
- When adding non-trivial logic, write a test for it. Behavior, not internals.
- If an existing test fails, fix the root cause — don't paper over it.

## Workspace layout

Two arrangements, picked per project depending on whether any code is meant
to be public.

**Layout A — purely private (one repo at workspace root):**

```
/workspace/
├── CLAUDE.md, STATUS.md, .claude/   ← agent state
├── src/, tests/, ...                ← code
└── .git/                            ← one repo, remote: `private` (your server)
```

Agent state and code share one git. The only remote is `private`. Nothing public, nothing leaks. Use this for solo or internal projects.

**Layout B — has public code (outer agent-state repo + inner code repo):**

```
/workspace/
├── CLAUDE.md, STATUS.md, .claude/   ← agent state
├── .gitignore                       ← lists each inner repo dir
├── .git/                            ← outer repo, remote: `private`
└── <project>/
    ├── src/, tests/, ...            ← code
    └── .git/                        ← inner repo, remote: `origin` (GitHub)
                                              + optionally `private`
```

Two independent gits with different remotes and different cadences. The outer `.gitignore` lists `<project>/` so git doesn't try to track it as a submodule. The inner repo *cannot* see `../CLAUDE.md` or `../.claude/` — its root is `<project>/` — so agent state is structurally insulated.

Multiple inner repos are allowed: every immediate subdirectory of `/workspace/` whose toplevel is its own `.git/` is treated as a separate inner project.

## Git

### Two streams

|                    | Outer (private)                  | Inner (public)                          |
|--------------------|----------------------------------|-----------------------------------------|
| Tracks             | agent state (+ private code in A)| source code                             |
| Remote             | `private` (your server)          | `origin` (GitHub) + optional `private`  |
| Commit cadence     | every machine switch (auto)      | only when work functions end-to-end     |
| Commit style       | `wip: handoff at <ts>` is fine   | clean atomic, message explains *why*    |
| Pre-commit gate    | skipped (sync only)              | formatter → linter → typecheck → tests  |
| Force-push allowed | yes (`--force-with-lease`)       | no — never                              |

Layout A has no inner stream — the outer rules apply to everything.

### Universal rules

- Never commit unless I ask. When I do, atomic commits with a short message explaining the *why*.
- For *public* commits (anything pushed to `origin`): the full pre-commit gate must pass. Fix at the source; never `--no-verify`.
- No "Generated with Claude Code" footers or co-author lines.
- Don't force-push public history, amend published commits, or delete branches without confirmation.

### Remote naming

- `private` — your sync server. Always set up.
- `origin` — only on inner repos with public history (e.g. GitHub).

Per-repo setup:
```
git remote add private <ssh-url>
```
On the server (once per repo, via SSH):
```
git config receive.denyCurrentBranch updateInstead
```
This makes the server's working tree update automatically on push, so you don't need to re-pull when you SSH in.

## Multi-machine sync

You typically work in two locations sharing one private sync server. The
server is the **hub**: it receives pushes, serves pulls, never pushes itself.
Only the laptops/clients run sync scripts.

### Scripts

Both live at `/workspace/.claude/scripts/`:

- `claude-handoff.sh [optional message]` — walks every git repo under `/workspace/`, commits any WIP, pushes to `private`. Run **before stepping away** from a machine.
- `claude-resume.sh` — walks every git repo under `/workspace/`, fetches from `private`, resets the working tree to `private/<current-branch>`. Refuses if uncommitted changes exist. Run **when arriving** at a machine.

Both skip repos that don't have a `private` remote, so a mixed setup (e.g. an inner repo whose `private` you haven't configured yet) is safe.

### The flow

```
LAPTOP                                      SERVER
─────                                       ──────
work, edit, …
claude-handoff   ──push──►                  working tree auto-updates
                                            (via receive.denyCurrentBranch=updateInstead)

                                            SSH in, work, commit normally.
                                            (server doesn't push.)

claude-resume    ◄──pull──                  
work, edit, …
```

The server runs nothing. Its tree updates from your push, its commits are pulled by `claude-resume`.

### Cleaning up wip before going public (Layout B only)

When code in an inner repo is ready to ship:

```
cd /workspace/<project>
git rebase -i origin/main           # squash wip commits into clean atomic ones
# pre-commit gate: formatter → linter → typecheck → tests — fix any failures
git push origin <branch>             # publish to GitHub

cd /workspace
claude-handoff                        # propagate cleaned-up history to your server
```

After the rebase, `claude-handoff` will force-push the inner repo to `private` (fine — wip history is yours to rewrite). `git push origin` should never need force.

## PRs
- Each PR is one complete behavior (tests + impl + actual usage). Don't land
  infrastructure without something using it.

## Skills (auto-improvement)
Persist *procedural* knowledge — "how I solved X" — as reusable skill docs
so future sessions start faster. Complements auto-memory (which stores
*declarative* facts: user, project, feedback, reference).

- **When to write a skill**: after finishing a task that used ~5+ tool calls
  *and* the approach would plausibly help in a future session. Skip for
  one-off debugging where the only takeaway is "read the code."
- **Where**:
  - `~/.claude/skills/<name>/SKILL.md` for cross-project skills — Claude
    Code's default user-scope path, auto-symlinked into every claudebox
    container by the entrypoint, so writes from the host reach every project.
  - `/workspace/.claude/skills/<name>/SKILL.md` for skills specific to one
    project (auto-loaded for that project only).
  - Each skill is a *directory* containing `SKILL.md` (required) plus any
    supporting files. Single-file `.md` skills are not recognized.
- **SKILL.md format**: YAML frontmatter (`name`, `description`) followed by
  the body. Claude Code triggers a skill by matching its description against
  the current task — make the description specific, not vague.

  ```
  ---
  name: my-skill
  description: When test passes locally but fails in CI, ...
  ---

  # body
  ```
- **What to capture**: the approach, edge cases hit, domain knowledge
  discovered, the shape of the investigation. *Not* specific file paths or
  a play-by-play of tool calls — those rot fast.
- **Edit in place, don't duplicate.** If an existing skill applies but is
  incomplete or wrong, fix it — don't write a near-duplicate.
- **Delete skills that proved wrong.** A misleading skill is worse than none.
- **Skills vs. auto-memory exclusions**: auto-memory forbids saving code
  patterns / architecture (derivable from the repo). Skills are procedural
  recipes ("how I investigated a flaky test"), not codebase facts —
  different category, allowed.

## Scripts (reusable procedures)
When a task is a repeatable procedure (install deps on a new slot, clean
build artifacts, run a migration), proactively propose saving it as a
script — don't wait to be asked. A 20-line script beats re-reading and
re-typing prose every time.

- **Where**: `/workspace/.claude/scripts/<slug>.sh` (or appropriate extension).
  Tracked by the workspace git.
- **Manifest**: `/workspace/.claude/scripts/README.md` — one line per script:
  *what it does, when to run it, last verified YYYY-MM-DD*. A script
  without a manifest entry is invisible.
- **Propose, then get approval before creating.** Don't silently add
  executables — an agent that writes a script will later run it, so a
  human needs to confirm before creation.
- **Verify before trusting an existing script.** Paths and tool versions
  drift. Re-read it, check the "last verified" date, dry-run if unsure.
  Update the date after a successful run.
- **Pair with skills.** A skill says *when/why*; a script is *how*.
  Cross-reference them.

## Plans & project status
Agent state lives under `/workspace/` and is tracked by the workspace git. One
predictable place per category so state doesn't drift:

- `/workspace/STATUS.md` — project heartbeat (done / in-progress / blocked / next).
- `/workspace/.claude/plans/<slug>.md` — plan for a non-trivial task; archive when done.
- `/workspace/.claude/decisions/NNN-<slug>.md` — long-lived "why X over Y" records
  (ADRs), numbered sequentially. Append-only; supersede via a new decision.
- In-session todos → `TaskCreate` (ephemeral, don't persist to disk).
- Ephemeral project context (merge freezes, current blockers) →
  auto-memory `project` type.
- Update STATUS + the active plan at task close (see self-nudge).

If something needs to reach teammates (e.g. a real ADR), put it inside the
inner repo at `<project>/docs/` — the outer repo is private to you.

## Self-nudge at task close
At the end of any non-trivial task, pause and ask: did this reveal something
non-obvious about **the user**, **the project**, or produce a **reusable
approach**? If yes, write the relevant memory (user / feedback / project /
reference) or skill *before* closing out. In-flight noticing misses things;
a deliberate end-of-task check catches them.

Then: commit meaningful agent-state changes to the outer repo, and run
`claude-handoff` if you're about to switch machines.

Skip the nudge for trivial tasks (one-line edits, pure Q&A with no new
learning).
