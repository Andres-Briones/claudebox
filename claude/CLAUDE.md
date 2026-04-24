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

## Git
- Never commit unless I ask. When I do, make atomic commits with a short message
  explaining the *why*.
- **Commit as soon as a logical unit is done** — don't batch unrelated changes
  into one big diff. Splitting a pile of mixed edits into clean commits after
  the fact is painful and wastes effort.
- No "Generated with Claude Code" footers or co-author lines.
- Don't force-push, amend published commits, or delete branches without confirmation.
- Before committing: formatter → linter → type-checker → tests. Fix failures
  at the source; don't disable checks or use `--no-verify`.
- `.claude/` and `CLAUDE.md` are `.gitignore`d by default — agent-local state
  (skills, scripts, plans, decisions) is shared across slots via the repo mount
  but not committed. If something needs to reach teammates, put it outside
  `.claude/`.

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
- **Where**: `/workspace/.claude/skills/<slug>.md`. Shared across slots via
  the repo mount, not committed (see `.gitignore`).
- **Manifest**: `/workspace/.claude/skills/README.md` — one line per skill:
  *trigger (specific, not vague), what it does, last updated*. A skill
  without a manifest entry is invisible.
- **Trigger must be specific.** "Debugging stuff" won't match; "test passes
  locally but fails in CI" will.
- **What to capture**: the approach, edge cases hit, domain knowledge
  discovered, the shape of the investigation. *Not* specific file paths or
  a play-by-play of tool calls — those rot fast.
- **Before starting similar work**: check the manifest for matching triggers.
  If a skill applies but is incomplete or wrong, *edit it in place* — don't
  write a near-duplicate.
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
  Shared across slots via the repo mount, not committed (see `.gitignore`).
  If a script needs to be shared with teammates, it belongs outside `.claude/`.
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
Agent state lives under `/workspace/.claude/` — shared across slots via the
repo mount, but not committed. If something needs to be shared with teammates
(e.g. a real ADR), put it outside `.claude/`. One predictable place per
category so state doesn't drift:

- `/workspace/.claude/STATUS.md` — project heartbeat (done / in-progress / blocked / next).
- `/workspace/.claude/plans/<slug>.md` — plan for a non-trivial task; archive when done.
- `/workspace/.claude/decisions/NNN-<slug>.md` — long-lived "why X over Y" records
  (ADRs), numbered sequentially. Append-only; supersede via a new decision.
- In-session todos → `TaskCreate` (ephemeral, don't persist to disk).
- Ephemeral project context (merge freezes, current blockers) →
  auto-memory `project` type.
- Update STATUS + the active plan at task close (see self-nudge).

## Versioning agent-local state
`.claude/` is gitignored in the main repo (private), but its *contents* are
worth tracking — skills evolve, plans get revised, decisions supersede each
other. Use a nested git repo scoped to agent state:

- `git init` inside `/workspace/.claude/` on new projects.
- Move the project CLAUDE.md into `/workspace/.claude/CLAUDE.md` and symlink
  `/workspace/CLAUDE.md` → `.claude/CLAUDE.md` so Claude Code still auto-loads it.
- Commit meaningful changes at task close (alongside the self-nudge).
- Never push this inner repo anywhere public — it's a local history tool,
  not a distribution channel.

The inner repo is shared across slots via the repo mount, invisible to
teammates, and gives you diff/blame/rollback for agent-local state.

## Self-nudge at task close
At the end of any non-trivial task, pause and ask: did this reveal something
non-obvious about **the user**, **the project**, or produce a **reusable
approach**? If yes, write the relevant memory (user / feedback / project /
reference) or skill *before* closing out. In-flight noticing misses things;
a deliberate end-of-task check catches them.

Skip the nudge for trivial tasks (one-line edits, pure Q&A with no new
learning).
