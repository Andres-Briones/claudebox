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

### Serving web apps to the user

The user's browser only reaches ports published at slot start
(`$CLAUDEBOX_PUBLISHED_PORTS`). Before starting a server the user will open,
use the `serve-web-app` skill. Don't widen exposure on your own: no
`0.0.0.0` bind on the host, `--disable-firewall`, or tunnel services (ngrok,
cloudflared) without stating the risk and getting the user's OK.

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

The harness prompts before any write to `.claude/`, even in
`--dangerously-skip-permissions` mode, which would block every "save a
skill" cycle on a confirm. The workaround is a parallel `.agent/` directory
of symlinks into `.claude/`:

```
.agent/
├── agents -> ../.claude/agents
├── scripts -> ../.claude/scripts
└── skills -> ../.claude/skills
```

Permission matching uses the literal tool-call path (no symlink resolution),
so writes via `.agent/...` run without a prompt, and the harness still
discovers the files under `.claude/`.

When writing skills, scripts, or agent definitions, use `.agent/...` paths.
Plans, decisions, and project state live at `.planning/`, outside `.claude/`,
so they need no workaround. Edit `.claude/...` directly only for content
that should be gated (settings, hooks).

If the symlinks aren't set up in your workspace yet, run once at the
workspace root:

```bash
mkdir -p .claude/agents .claude/skills .claude/scripts .agent .planning/plans .planning/decisions
ln -s ../.claude/agents  .agent/agents
ln -s ../.claude/skills  .agent/skills
ln -s ../.claude/scripts .agent/scripts
```

## Skills (auto-improvement)
Persist *procedural* knowledge — "how I solved X" — as reusable skill docs
so future sessions start faster. Complements auto-memory (which stores
*declarative* facts: user, project, feedback, reference).

- **When to write a skill**: after finishing a task that used ~5+ tool calls
  *and* the approach would plausibly help in a future session. Skip for
  one-off debugging where the only takeaway is "read the code."
- **Where**:
  - `/workspace/.agent/skills/<name>/SKILL.md` for anything you write from
    inside a container. It is loaded for this project and tracked by the
    workspace git.
  - Cross-project skills live in the **host's** `~/.claude/skills/<name>/`,
    which the entrypoint links read-only into every container. A skill
    written to `~/.claude/skills/` from inside a container stays in that one
    slot, so if a skill deserves to be cross-project, write it to the
    workspace and tell the user to copy it to the host.
  - Each skill is a *directory* containing `SKILL.md` (required) plus any
    supporting files. Single-file `.md` skills are not recognized.
- **SKILL.md format**: YAML frontmatter (`name`, `description`) followed by
  the body. Claude Code triggers a skill by matching its description against
  the current task — make the description specific ("When a test passes
  locally but fails in CI, ..."), not vague.
- **What to capture**: the approach, edge cases hit, domain knowledge
  discovered, the shape of the investigation. *Not* specific file paths or
  a play-by-play of tool calls — those rot fast.
- **Edit in place, don't duplicate.** If an existing skill applies but is
  incomplete or wrong, fix it — don't write a near-duplicate.
- **Delete skills that proved wrong.** A misleading skill is worse than none.
- **Skills vs. auto-memory**: memory excludes code patterns and architecture;
  skills are procedural recipes, a different category, and are allowed.

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

## Delegating to agents
A subagent re-reads its whole history at every step, so a long-running
worker costs far more than several short ones. Keep workers short.

- One worker = one result that fits a short session. Split by deliverable
  or by batch, and run the pieces in parallel or in sequence from files.
- Every brief names the result to produce (a file, a passing test), a stop
  point ("when X exists and tests pass, stop") and a budget (about 60 tool
  calls, then write a handoff file and report). It also says: no whole-file
  dumps, no polling of background runs, no polishing rounds.
- Continue from the handoff file with a fresh worker rather than resuming a
  long one. Long computations run in the background from the main session.
- Before launching, tell the user each job in one line with the result it
  must produce. Afterwards, list every result against the user's goal and
  say plainly what is still missing.
- While workers write in a tree, commit only your own files by name.
- For a new block of work in a very long session, suggest a fresh session
  and have `.planning/STATE.md` ready for it.

## Plans & project status
All project state lives under `/workspace/.planning/` (shared cleanly with
the GSD toolkit, which writes its own files at the `.planning/` root).

- `/workspace/.planning/STATE.md` — project heartbeat (done / in-progress / blocked / next).
- `/workspace/.planning/plans/<slug>.md` — plan for a non-trivial task; archive when done.
- `/workspace/.planning/decisions/NNN-<slug>.md` — long-lived "why X over Y" records
  (ADRs), numbered sequentially. Append-only; supersede via a new decision.
- In-session todos → the built-in task tool (ephemeral, don't persist to disk).
- Ephemeral project context (merge freezes, current blockers) →
  auto-memory `project` type.
- Update STATE + the active plan at task close (see self-nudge). Write STATE
  last, after every worker has finished and its work is committed, with
  numbers read from the data at that moment. Never close a session on
  "in progress" or "not committed".

To migrate a workspace still on the older `STATUS.md` + `.agent/plans/` +
`.agent/decisions/` layout, invoke the `migrate-to-planning` skill.

## Self-nudge at task close
At the end of any non-trivial task, pause and ask: did this reveal something
non-obvious about **the user**, **the project**, or produce a **reusable
approach**? If yes, write the relevant memory (user / feedback / project /
reference) or skill *before* closing out. In-flight noticing misses things;
a deliberate end-of-task check catches them.

Skip the nudge for trivial tasks (one-line edits, pure Q&A with no new
learning).
