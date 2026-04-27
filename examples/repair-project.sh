#!/usr/bin/env bash
# Repair a claudebox project parent dir whose slots got broken by Docker
# auto-creating root-owned paths under .claude/projects/-workspace during
# the shared-memory bind-mount window (causes new-project history to fail
# to save and `claudebox resume` to find nothing).
#
# For each slot under the given parent it:
#   - copies any *.jsonl session files out to <parent>/.rescue/<slot>/
#     (skip with --purge)
#   - removes the broken .claude/projects subtree
# After relaunching claudebox once, the slot recreates the dir cleanly and
# you can copy the rescued files back to <slot>/.claude/projects/-workspace/.
#
# Works without sudo in both rootful and rootless Docker — the cleanup runs
# inside a throwaway container that inherits the privileges Docker used to
# create the broken paths.
#
# Usage:
#   ./repair-project.sh <parent-dir>
#   ./repair-project.sh --purge <parent-dir>     # skip rescue, just wipe
#
# Example:
#   ./repair-project.sh ~/.claudebox/projects/home_andres_documents_proj_a683bd2a

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
    printf 'Usage: %s [--purge] <parent-dir>\n' "$(basename "$0")" >&2
    exit 1
}

PURGE=false
PARENT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --purge) PURGE=true; shift ;;
        -h|--help) usage ;;
        -*) printf 'Unknown option: %s\n' "$1" >&2; usage ;;
        *) PARENT="$1"; shift ;;
    esac
done

if [ -z "$PARENT" ] || [ ! -d "$PARENT" ]; then
    usage
fi

PARENT=$(cd "$PARENT" && pwd)

# Pick a locally-pulled image with /bin/sh.
IMG=""
for c in claudebox busybox alpine; do
    if docker image inspect "$c" >/dev/null 2>&1; then
        IMG="$c"
        break
    fi
done
if [ -z "$IMG" ]; then
    extra=$(docker images --filter 'reference=claudebox-*' --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | head -1 || true)
    if [ -n "$extra" ]; then
        IMG="$extra"
    fi
fi
if [ -z "$IMG" ]; then
    printf 'No suitable image found locally; pulling busybox...\n'
    docker pull busybox >/dev/null
    IMG="busybox"
fi

RESCUE_ROOT="$PARENT/.rescue"
if [ "$PURGE" != "true" ]; then
    mkdir -p "$RESCUE_ROOT"
fi

REPAIRED=0
for slot in "$PARENT"/*/; do
    if [ ! -d "$slot" ]; then
        continue
    fi
    name=$(basename "$slot")
    case "$name" in
        commands|allowlist|.rescue) continue ;;
    esac

    claude_dir="${slot}.claude"
    if [ ! -d "$claude_dir/projects" ]; then
        continue
    fi

    printf 'Repairing slot: %s\n' "$name"

    if [ "$PURGE" = "true" ]; then
        docker run --rm -v "$claude_dir":/c --entrypoint sh "$IMG" \
            -c 'rm -rf /c/projects' >/dev/null
    else
        out="$RESCUE_ROOT/$name"
        mkdir -p "$out"
        docker run --rm \
            -v "$claude_dir":/c -v "$out":/out \
            --entrypoint sh "$IMG" -c '
                if [ -d /c/projects/-workspace ]; then
                    find /c/projects/-workspace -maxdepth 1 -name "*.jsonl" \
                        -exec cp -a {} /out/ \; 2>/dev/null || true
                fi
                rm -rf /c/projects
            ' >/dev/null

        if [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
            printf '  rescued %d session(s) -> %s\n' \
                "$(find "$out" -maxdepth 1 -name '*.jsonl' | wc -l | tr -d ' ')" \
                "$out"
        else
            rmdir "$out" 2>/dev/null || true
        fi
    fi

    REPAIRED=$((REPAIRED + 1))
done

printf 'Done. Repaired %d slot(s).\n' "$REPAIRED"
if [ "$PURGE" != "true" ] \
   && [ -d "$RESCUE_ROOT" ] \
   && [ -n "$(ls -A "$RESCUE_ROOT" 2>/dev/null)" ]; then
    printf '\nRescued sessions live under: %s\n' "$RESCUE_ROOT"
    printf 'After relaunching claudebox once per slot, copy them back:\n'
    printf '  cp -a "%s/<slot>/." "%s/<slot>/.claude/projects/-workspace/"\n' \
        "$RESCUE_ROOT" "$PARENT"
fi
