#!/usr/bin/env bash
# gsd-install.sh — install/update the GSD (Get Shit Done) markdown payload
# into ~/.claude/{skills,agents,commands}/gsd/ for use inside ClaudeBox slots.
#
# Pair this with `claudebox add gsd` (which adds @gsd-build/sdk to the image).
# This script populates the host-side markdown that ClaudeBox auto-mounts
# into every slot.
#
# Usage:
#   scripts/gsd-install.sh              # minimal install (6 core skills)
#   scripts/gsd-install.sh --full       # full install (all skills + agents)
#   scripts/gsd-install.sh --update     # git pull + re-copy
#   scripts/gsd-install.sh --uninstall  # remove ~/.claude/*/gsd/
#
# Idempotent. Re-running with the same flags is safe.

set -Eeuo pipefail
IFS=$'\n\t'

readonly GSD_REPO="https://github.com/gsd-build/get-shit-done.git"
readonly GSD_SRC="${HOME}/src/gsd"
readonly CLAUDE_HOME="${HOME}/.claude"

# Minimal install: the 6 core skills documented as the canonical small set.
# Mirrors the upstream `--minimal` flag in bin/lib/install.cjs.
readonly MINIMAL_SKILLS=(new-project discuss plan execute help update)

usage() {
    cat <<'EOF'
gsd-install.sh — install GSD markdown payload for ClaudeBox slots

Usage:
  scripts/gsd-install.sh              minimal install (6 core skills)
  scripts/gsd-install.sh --full       full install (all skills + agents)
  scripts/gsd-install.sh --update     git pull + re-copy current selection
  scripts/gsd-install.sh --uninstall  remove ~/.claude/{skills,agents,commands}/gsd/
  scripts/gsd-install.sh --help       this message

Pair with `claudebox add gsd` to install the @gsd-build/sdk CLI into the image.
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

install_minimal() {
    log "Installing minimal GSD set (${#MINIMAL_SKILLS[@]} skills)..."
    local skills_dst="${CLAUDE_HOME}/skills/gsd"
    rm -rf "$skills_dst"
    mkdir -p "$skills_dst"
    local s
    for s in "${MINIMAL_SKILLS[@]}"; do
        if [ -d "${GSD_SRC}/skills/${s}" ]; then
            cp -r "${GSD_SRC}/skills/${s}" "${skills_dst}/${s}"
        else
            log "  warn: minimal skill not found upstream: ${s}"
        fi
    done

    # Minimal install includes matching commands when they exist.
    local cmds_dst="${CLAUDE_HOME}/commands/gsd"
    rm -rf "$cmds_dst"
    if [ -d "${GSD_SRC}/commands" ]; then
        mkdir -p "$cmds_dst"
        for s in "${MINIMAL_SKILLS[@]}"; do
            local cmd_file="${GSD_SRC}/commands/${s}.md"
            if [ -f "$cmd_file" ]; then
                cp "$cmd_file" "${cmds_dst}/${s}.md"
            fi
        done
    fi
}

install_full() {
    log "Installing full GSD payload..."
    mirror_dir "${GSD_SRC}/skills"   "${CLAUDE_HOME}/skills/gsd"
    mirror_dir "${GSD_SRC}/agents"   "${CLAUDE_HOME}/agents/gsd"
    mirror_dir "${GSD_SRC}/commands" "${CLAUDE_HOME}/commands/gsd"
}

uninstall() {
    log "Removing GSD payload from ${CLAUDE_HOME}/{skills,agents,commands}/gsd/..."
    rm -rf "${CLAUDE_HOME}/skills/gsd"
    rm -rf "${CLAUDE_HOME}/agents/gsd"
    rm -rf "${CLAUDE_HOME}/commands/gsd"
    log "Done. (~/src/gsd left in place; remove manually if desired.)"
}

# Detect prior install mode by looking at ~/.claude/agents/gsd existence.
# Full install ships agents; minimal does not.
detect_mode() {
    if [ -d "${CLAUDE_HOME}/agents/gsd" ]; then
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

    clone_or_update_gsd

    if [ "$do_update" = "true" ]; then
        mode="$(detect_mode)"
        log "Detected prior install mode: ${mode}"
    fi

    case "$mode" in
        minimal) install_minimal ;;
        full)    install_full ;;
    esac

    log ""
    log "Done. GSD payload installed at:"
    log "  ${CLAUDE_HOME}/skills/gsd/"
    [ -d "${CLAUDE_HOME}/agents/gsd" ]   && log "  ${CLAUDE_HOME}/agents/gsd/"
    [ -d "${CLAUDE_HOME}/commands/gsd" ] && log "  ${CLAUDE_HOME}/commands/gsd/"
    log ""
    log "Next: run \`claudebox add gsd\` (once per project) to install the"
    log "@gsd-build/sdk CLI into the slot image, then launch claudebox."
}

main "$@"
