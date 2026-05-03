#!/usr/bin/env bash
# gsd-install.sh — install/update the GSD (Get Shit Done) markdown payload
# into a host-side staging dir at ~/.claude/gsd/.
#
# This script never writes to ~/.claude/{commands,agents,hooks} or
# ~/.claude/get-shit-done directly. The staging dir is inert until a slot's
# `gsd` profile is active — at slot launch, build/docker-entrypoint reads
# the slot's profiles.ini and, only if `gsd` is present, symlinks the
# staged content into the slot's live dirs and jq-merges settings.gsd.json
# into the slot's settings.json.
#
# Pair this with `claudebox add gsd` (which adds the gsd profile to the
# project's profiles.ini and installs get-shit-done-cc into the image).
#
# Layout of the upstream payload (gsd-build/get-shit-done) and where each
# piece lands in the staging dir:
#   commands/gsd/<name>.md          →  ~/.claude/gsd/commands/gsd/<name>.md
#   get-shit-done/workflows/        →  ~/.claude/gsd/workflows/
#                                      (only the workflows subdir; bin/lib
#                                      not needed for our minimal install)
#   agents/gsd-<name>.md            →  ~/.claude/gsd/agents/gsd-<name>.md
#                                      (--full only)
#   hooks/gsd-*.{js,sh}             →  ~/.claude/gsd/hooks/gsd-*
#                                      (always installed; excluded set below)
#   claudebox/claude/settings.gsd.json  →  ~/.claude/gsd/settings.gsd.json
#                                      (the hook registrations fragment;
#                                      sourced from this fork's seed dir)
#
# Usage:
#   scripts/gsd-install.sh              # minimal install (5 commands + workflows + hooks + fragment)
#   scripts/gsd-install.sh --full       # full install (all commands + agents + workflows + hooks + fragment)
#   scripts/gsd-install.sh --update     # git pull + re-copy current selection
#   scripts/gsd-install.sh --uninstall  # remove ~/.claude/gsd + sweep legacy paths
#
# Idempotent. Re-running with the same flags is safe.

set -Eeuo pipefail
IFS=$'\n\t'

readonly GSD_REPO="https://github.com/gsd-build/get-shit-done.git"
readonly GSD_SRC="${HOME}/src/gsd"
readonly STAGING="${HOME}/.claude/gsd"

# Resolve the fork seed dir relative to this script: scripts/gsd-install.sh
# lives at <fork>/scripts/, so the seed is at <fork>/claude/.
FORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly FORK_DIR
readonly SEED_FRAGMENT="${FORK_DIR}/claude/settings.gsd.json"

# Minimal install: 5 core commands. Upstream's MINIMAL_SKILL_ALLOWLIST
# (get-shit-done/bin/lib/install-profiles.cjs) ships 6 — we drop `update`
# because /gsd:update runs `npx get-shit-done-cc@latest --claude --global`,
# which fights this installer's staging-dir design. Refresh by re-running
# this script with --update instead.
readonly MINIMAL_COMMANDS=(new-project discuss-phase plan-phase execute-phase help)

# Hooks that ship in upstream's hooks/ but should NOT be installed:
#   - gsd-workflow-guard.js: opinionated workflow guardrail not desired here.
#   - gsd-check-update.js + worker: update flow conflicts with seed-baked
#     install (see /gsd:update notes in the project STATE).
readonly EXCLUDED_HOOKS=(
    gsd-workflow-guard.js
    gsd-check-update.js
    gsd-check-update-worker.js
)

# Hooks referenced by registrations in the seed settings.gsd.json fragment.
# Validated post-install; warns if any are missing. Keep in sync with the
# fragment — drift causes silent hook failures inside slots.
readonly EXPECTED_HOOKS=(
    gsd-statusline.js
    gsd-context-monitor.js
    gsd-prompt-guard.js
    gsd-read-guard.js
    gsd-read-injection-scanner.js
    gsd-phase-boundary.sh
    gsd-session-state.sh
    gsd-validate-commit.sh
)

# Legacy paths from the pre-staging install layout. Cleaned up by uninstall
# and warned about (but not auto-removed) by install_*, since they may
# contain user content that predates this script.
readonly LEGACY_PATHS=(
    "${HOME}/.claude/commands/gsd"
    "${HOME}/.claude/agents/gsd"
    "${HOME}/.claude/get-shit-done"
)

usage() {
    cat <<'EOF'
gsd-install.sh — install GSD payload into ~/.claude/gsd/ staging dir

Usage:
  scripts/gsd-install.sh              minimal install (5 commands + workflows + hooks + fragment)
  scripts/gsd-install.sh --full       full install (all commands + agents + workflows + hooks + fragment)
  scripts/gsd-install.sh --update     git pull + re-copy current selection
  scripts/gsd-install.sh --uninstall  remove ~/.claude/gsd + sweep legacy paths
  scripts/gsd-install.sh --help       this message

The staging dir is inert until a slot has the `gsd` profile in its
profiles.ini — at that point build/docker-entrypoint wires it into the slot.

Pair with `claudebox add gsd` (per project) to add the profile and install
the get-shit-done-cc CLI (which ships gsd-sdk with the full query subcommand) into the slot image.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

clone_or_update_gsd() {
    if [ -d "${GSD_SRC}/.git" ]; then
        log "Updating ${GSD_SRC} (git pull)..."
        git -C "${GSD_SRC}" pull --ff-only
    else
        log "Cloning GSD into ${GSD_SRC}..."
        mkdir -p "$(dirname "${GSD_SRC}")"
        git clone --depth 1 "${GSD_REPO}" "${GSD_SRC}"
    fi
}

# Mirror $1 into $2 atomically: rm -rf $2, then cp -r $1 $2.
# Used so re-runs reflect upstream removals/renames.
mirror_dir() {
    local src="$1"
    local dst="$2"
    if [ ! -d "$src" ]; then
        log "skip: source dir missing: $src"
        return 0
    fi
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
}

warn_legacy() {
    local p found=0
    for p in "${LEGACY_PATHS[@]}"; do
        if [ -e "$p" ]; then
            if [ "$found" = "0" ]; then
                log ""
                log "warn: legacy GSD paths from a pre-staging install detected:"
                found=1
            fi
            log "  - ${p}"
        fi
    done
    if [ "$found" = "1" ]; then
        log "  These are no longer maintained by this script. Run with"
        log "  --uninstall first to clean them up, then re-run install."
        log ""
    fi
    # Also warn if hooks/gsd-* lingers from the legacy flat-install location.
    if compgen -G "${HOME}/.claude/hooks/gsd-*" >/dev/null 2>&1; then
        log "warn: legacy ~/.claude/hooks/gsd-* files detected — --uninstall sweeps them."
        log ""
    fi
}

# Install the workflows payload. Command stubs `@`-reference
# ~/.claude/get-shit-done/workflows/<name>.md; the activation step in the
# entrypoint creates that path as a symlink to here.
install_workflows() {
    local src="${GSD_SRC}/get-shit-done/workflows"
    local dst="${STAGING}/workflows"
    if [ ! -d "$src" ]; then
        die "upstream payload missing: $src (re-run with --update?)"
    fi
    log "  installing workflows → ${dst}/"
    mirror_dir "$src" "$dst"
}

is_excluded_hook() {
    local name="$1"
    local exc
    for exc in "${EXCLUDED_HOOKS[@]}"; do
        if [ "$name" = "$exc" ]; then
            return 0
        fi
    done
    return 1
}

# Install GSD hook scripts to the staging hooks/ dir (flat, gsd-* prefixed).
# The activation step in the entrypoint per-file-symlinks them into the
# slot's ~/.claude/hooks/. Excludes EXCLUDED_HOOKS.
install_hooks() {
    local src="${GSD_SRC}/hooks"
    local dst="${STAGING}/hooks"

    if [ ! -d "$src" ]; then
        log "  note: no hooks/ dir in upstream payload — skipping hooks"
        return 0
    fi

    rm -rf "$dst"
    mkdir -p "$dst"

    local f basename copied=0 skipped=0
    for f in "${src}"/gsd-*; do
        if [ ! -f "$f" ]; then
            continue
        fi
        basename=$(basename "$f")
        if is_excluded_hook "$basename"; then
            skipped=$((skipped + 1))
            continue
        fi
        cp "$f" "${dst}/${basename}"
        chmod +x "${dst}/${basename}"
        copied=$((copied + 1))
    done

    log "  installed ${copied} hooks → ${dst}/ (skipped ${skipped} per EXCLUDED_HOOKS)"
}

# Copy the seed settings fragment from the fork. The activation step
# jq-merges this into the slot's settings.json.
install_settings_fragment() {
    local dst="${STAGING}/settings.gsd.json"
    if [ ! -f "$SEED_FRAGMENT" ]; then
        die "seed fragment missing: ${SEED_FRAGMENT} — fork install incomplete?"
    fi
    mkdir -p "$STAGING"
    cp "$SEED_FRAGMENT" "$dst"
    log "  installed settings fragment → ${dst}"
}

# Warn if any hook the seed fragment registers is missing on disk.
# A missing registered hook fails on every event fire inside a slot.
validate_hooks() {
    local missing=0
    local h
    for h in "${EXPECTED_HOOKS[@]}"; do
        if [ ! -f "${STAGING}/hooks/${h}" ]; then
            log "  warn: registered hook missing: ${h}"
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        log "  ${missing} hook(s) registered in settings.gsd.json but absent."
        log "  Either re-run install, or update claudebox/claude/settings.gsd.json"
        log "  to drop the registration + EXPECTED_HOOKS in this script."
    fi
}

install_minimal() {
    log "Installing minimal GSD set (${#MINIMAL_COMMANDS[@]} commands + workflows + hooks + fragment)..."
    local cmds_src="${GSD_SRC}/commands/gsd"
    local cmds_dst="${STAGING}/commands/gsd"

    if [ ! -d "$cmds_src" ]; then
        die "upstream payload missing: $cmds_src (re-run with --update?)"
    fi

    rm -rf "$cmds_dst"
    mkdir -p "$cmds_dst"
    local s copied=0
    for s in "${MINIMAL_COMMANDS[@]}"; do
        local cmd_file="${cmds_src}/${s}.md"
        if [ -f "$cmd_file" ]; then
            cp "$cmd_file" "${cmds_dst}/${s}.md"
            copied=$((copied + 1))
        else
            log "  warn: minimal command not found upstream: ${s}.md"
        fi
    done
    log "  copied ${copied}/${#MINIMAL_COMMANDS[@]} commands → ${cmds_dst}/"

    install_workflows
    install_hooks
    install_settings_fragment
}

install_full() {
    log "Installing full GSD payload..."
    local cmds_src="${GSD_SRC}/commands/gsd"
    local agents_src="${GSD_SRC}/agents"

    if [ ! -d "$cmds_src" ]; then
        die "upstream payload missing: $cmds_src (re-run with --update?)"
    fi

    mirror_dir "$cmds_src" "${STAGING}/commands/gsd"

    # Agents ship as flat gsd-*.md files; copy them flat into staging/agents/.
    # The activation step per-file-symlinks them into the slot's agents/ dir.
    if [ -d "$agents_src" ]; then
        local agents_dst="${STAGING}/agents"
        rm -rf "$agents_dst"
        mkdir -p "$agents_dst"
        local f
        for f in "${agents_src}"/gsd-*.md; do
            if [ -f "$f" ]; then
                cp "$f" "${agents_dst}/$(basename "$f")"
            fi
        done
    else
        log "  note: no agents/ dir in upstream payload — skipping agents"
    fi

    install_workflows
    install_hooks
    install_settings_fragment
}

uninstall() {
    log "Removing GSD staging dir at ${STAGING}/..."
    rm -rf "${STAGING}"

    log "Sweeping legacy paths from pre-staging installs..."
    local p
    for p in "${LEGACY_PATHS[@]}"; do
        if [ -e "$p" ]; then
            rm -rf "$p"
            log "  removed ${p}"
        fi
    done
    if compgen -G "${HOME}/.claude/hooks/gsd-*" >/dev/null 2>&1; then
        rm -f "${HOME}"/.claude/hooks/gsd-*
        log "  removed ~/.claude/hooks/gsd-*"
    fi

    log "Done. (${GSD_SRC} left in place; remove manually if desired.)"
}

# Detect prior install mode by looking at the staging agents/ dir.
# Full install ships agents; minimal does not.
detect_mode() {
    if [ -d "${STAGING}/agents" ] && [ -n "$(ls -A "${STAGING}/agents" 2>/dev/null)" ]; then
        printf 'full\n'
    else
        printf 'minimal\n'
    fi
}

main() {
    local mode="minimal"
    local do_update=false

    case "${1:-}" in
        ""|--minimal)  mode="minimal" ;;
        --full)        mode="full" ;;
        --update)      do_update=true ;;
        --uninstall)   uninstall; exit 0 ;;
        -h|--help)     usage; exit 0 ;;
        *)             usage; die "unknown flag: $1" ;;
    esac

    command -v git >/dev/null || die "git not found on host (needed to clone GSD)"

    warn_legacy
    clone_or_update_gsd

    if [ "$do_update" = "true" ]; then
        mode="$(detect_mode)"
        log "Detected prior install mode: ${mode}"
    fi

    case "$mode" in
        minimal) install_minimal ;;
        full)    install_full ;;
    esac

    validate_hooks

    log ""
    log "Done. GSD staging populated at ${STAGING}/:"
    local d
    for d in "${STAGING}/commands/gsd" "${STAGING}/agents" "${STAGING}/workflows" "${STAGING}/hooks"; do
        if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
            log "  ${d}/ ($(find "$d" -type f | wc -l | tr -d ' ') files)"
        fi
    done
    if [ -f "${STAGING}/settings.gsd.json" ]; then
        log "  ${STAGING}/settings.gsd.json"
    fi
    log ""
    log "Next: in each project where you want GSD active, run"
    log "  claudebox add gsd"
    log "  claudebox rebuild"
    log "Slots without the gsd profile see no /gsd:* commands and no hooks."
}

main "$@"
