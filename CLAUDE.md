# CLAUDE.md

Guidance for Claude Code when working on this repository.

ClaudeBox is a Bash launcher that runs Claude Code inside per-project Docker
containers ("slots"). People run it daily on macOS and Linux, so stability
matters more than cleverness: read the code path you are changing end to end
before editing, keep changes minimal, and preserve existing behavior unless
asked to change it.

## Hard requirements

- **Bash 3.2 only** (the macOS default). No associative arrays, no `${var^^}`
  or `${var,,}`, no `[[ -v var ]]`, no `mapfile`/`readarray`, no `&>>`.
- **macOS and Linux userlands.** Avoid GNU-only flags (`grep -P`, `stat -c`,
  `readlink -f`, `sed -i` without a suffix argument). Use `command -v`, not
  `which`.
- **Never run `git restore`** (or otherwise discard uncommitted work) unless
  the user explicitly asks. If they do, `git stash` first.

## Design decisions that look wrong but are intentional

### Containers
- Containers are named **and** run with `--rm`. They are ephemeral: created,
  run, and auto-deleted on exit. Do not remove `--rm`.
- Do not try to delete containers on start; they no longer exist.
- There are no lock files. A running container's name is the lock, and
  `docker ps` is the source of truth for which slots are in use.

### Images
- One image is shared by all slots of a project, named after the parent
  (slot 0).
- Layer caching is deliberate. Do not force `--no-cache` and do not delete
  images during a rebuild; only changed layers should rebuild.

### Slots
- Slots start at 1. Slot 0 conceptually is the parent; a counter value of 0
  means no slots exist.
- Slot IDs are a CRC32 chain (slot N's ID is the CRC32 of slot N-1's ID), so
  the numbering cannot change without changing every hash. See
  `docs/slot-management-system.md` and `docs/checksum-and-naming-system.md`.

### CLI
- Arguments are sorted into four buckets (host-only flags, control flags,
  script commands, pass-through to Claude) in `lib/cli.sh`. A new subcommand
  must be added to `SCRIPT_COMMANDS` there, otherwise it is silently forwarded into the
  container. See `docs/cli-implementation.md`.

## Error handling under `set -euo pipefail`

`main.sh` runs with `set -euo pipefail`, so any command returning non-zero
exits the whole script. A bare `&&` chain is the usual way this bites:

```bash
# Wrong: exits the script whenever VERBOSE is not "true"
[[ "$VERBOSE" == "true" ]] && echo "Debug message"

# Right
if [[ "$VERBOSE" == "true" ]]; then
    printf 'Debug message\n' >&2
fi
```

- Use `if`/`then`/`fi` for conditional logic, not `&&` or `||`.
- If a command is allowed to fail, say so explicitly with `|| true` and only
  there.
- Do not send stderr to `/dev/null`; errors are needed for troubleshooting.
  Silence stdout only (`command >/dev/null`).

## Output

- No unnecessary output. Do not add a success or info message for every
  operation; debug detail goes behind `--verbose` (`$VERBOSE`).
- Use `printf` rather than `echo` in new code.

## Where things are

- `main.sh` is the entry point. It sources `lib/{cli,common,env,os,state,project,docker,config,commands,welcome,preflight}.sh`
  in that order; `lib/commands.sh` pulls in the `lib/commands.*.sh` handlers.
- Profiles are `get_profile_*` functions in `lib/config.sh` (functions, not
  arrays, for Bash 3.2).
- `build/` holds `Dockerfile`, `Dockerfile.project`, `docker-entrypoint` and
  `init-firewall`. Templates use `{{VAR}}` substitution.
- `claude/` is the seed config copied into every slot's `~/.claude/`
  (`CLAUDE.md`, `settings.json`, skills, agents). A change there reaches every
  session in every slot, so keep it small and test it in a fresh slot.
- `commands/` holds the slash commands synced into each project under the
  `cbox:` namespace.
- `.builder/build.sh` packs the repo into `dist/claudebox.run`. The version
  is `CLAUDEBOX_VERSION` near the top of `main.sh`.

## Testing

Run from the repository root:

```bash
bash tests/test_bash32_compat.sh      # Bash 3.2 compatibility, local Bash
bash tests/test_in_bash32_docker.sh   # same suite in real Bash 3.2 (needs Docker)
bash tests/test_mount.sh              # --mount parsing
bash tests/test_port_publish.sh       # --port parsing
bash tests/test_commands_sync.sh      # slash-command sync
bash -n main.sh                       # syntax check; repeat for edited lib files
```

CI (`.github/workflows/test.yml`) runs the compatibility suite on Linux and
macOS and lints with ShellCheck. Changes to `build/docker-entrypoint` or the
Dockerfiles are not covered by these tests; verify them by launching a fresh
slot.
