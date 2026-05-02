# Global preferences

These are defaults. A project's own CLAUDE.md overrides any rule here when
they conflict.

## Environment
- Tooling available in this container: @~/.claudebox/tooling.md

## Container environment

You're running inside an ephemeral claudebox slot. System-level changes
(`apt install`, files in `/etc`, `/usr`, etc.) vanish when the slot exits.
Only host-mounted paths persist: `/workspace`, `~/.claude/`, `~/.claudebox/`,
plus any extra mounts.

- **Tool installs**: don't ad-hoc `apt install`. Tell the user what's
  missing and recommend the claudebox profile system — `claudebox profiles`
  lists available profiles, `claudebox add <name>` enables one (run on the
  host, not inside the slot). For tooling with no matching profile, propose
  adding one to the fork's profile catalog (`lib/config.sh`) rather than
  reinstalling each session.

### Rootless docker

If the host runs rootless docker, the container's UID 1000 maps to a host
subuid (e.g. 100999). Symptoms: files written to host mounts appear owned
by an unexpected UID on the host, or permission-denied on paths that look
fine from inside. Quick check:

```bash
awk 'NR==1 && $2!="0"{print "rootless"}' /proc/self/uid_map
```

Fixes are host-side (rootlesskit chmod, subuid range) — surface the symptom
to the user with the offending path and observed ownership; don't try to
chmod across the userns boundary.

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
- `git config --global --add safe.directory <path>` is pre-approved — run it without asking when git refuses with "dubious ownership". This is the only sanctioned exception to the otherwise no-git-config rule.
- No "Generated with Claude Code" footers or co-author lines.
- Don't force-push public history, amend published commits, or delete branches without confirmation.

## PRs
- Each PR is one complete behavior (tests + impl + actual usage). Don't land
  infrastructure without something using it.

## Autonomous writes — the `.agent/` convention

The harness prompts before any write to `.claude/` even in
`--dangerously-skip-permissions` mode — a deliberate carve-out that protects
the harness's own config dir from runaway agents. That's the right default,
but it blocks autonomous self-improvement: every "save a skill" or "update
the plan" cycle would block on a confirm.

The workaround is a parallel `.agent/` directory of symlinks pointing into
`.claude/`:

```
.agent/
├── agents -> ../.claude/agents
├── decisions -> ../.claude/decisions
├── plans -> ../.claude/plans
├── scripts -> ../.claude/scripts
└── skills -> ../.claude/skills
```

Permission matching uses the literal tool-call path (no symlink resolution),
so writes via `.agent/...` skip the carve-out and run silently. Both paths
refer to the same files; the harness still auto-discovers content under
`.claude/`.

**Convention used below:** when writing skills, scripts, plans, decisions,
or agent definitions, use `.agent/...` paths. Direct `.claude/...` edits
remain appropriate for content that *should* be gated (settings, hooks).

If the symlinks aren't set up in your workspace yet, run once at the
workspace root:

```bash
mkdir -p .claude/agents .claude/skills .claude/scripts .claude/plans .claude/decisions .agent
ln -s ../.claude/agents    .agent/agents
ln -s ../.claude/skills    .agent/skills
ln -s ../.claude/scripts   .agent/scripts
ln -s ../.claude/plans     .agent/plans
ln -s ../.claude/decisions .agent/decisions
```

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
  - `/workspace/.agent/skills/<name>/SKILL.md` for skills specific to one
    project (auto-loaded for that project via the `.claude/skills/`
    symlink target).
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

- **Where**: `/workspace/.agent/scripts/<slug>.sh` (or appropriate extension).
  Tracked by the workspace git via the `.claude/scripts/` symlink target.
- **Manifest**: `/workspace/.agent/scripts/README.md` — one line per script:
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
One predictable place per category so state doesn't drift:

- `/workspace/STATUS.md` — project heartbeat (done / in-progress / blocked / next).
- `/workspace/.agent/plans/<slug>.md` — plan for a non-trivial task; archive when done.
- `/workspace/.agent/decisions/NNN-<slug>.md` — long-lived "why X over Y" records
  (ADRs), numbered sequentially. Append-only; supersede via a new decision.
- In-session todos → `TaskCreate` (ephemeral, don't persist to disk).
- Ephemeral project context (merge freezes, current blockers) →
  auto-memory `project` type.
- Update STATUS + the active plan at task close (see self-nudge).

## Self-nudge at task close
At the end of any non-trivial task, pause and ask: did this reveal something
non-obvious about **the user**, **the project**, or produce a **reusable
approach**? If yes, write the relevant memory (user / feedback / project /
reference) or skill *before* closing out. In-flight noticing misses things;
a deliberate end-of-task check catches them.

Skip the nudge for trivial tasks (one-line edits, pure Q&A with no new
learning).
