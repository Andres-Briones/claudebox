#!/usr/bin/env bash
# Tests for sync_commands_to_project: each bundled command must reach a
# project exactly once (under cbox/), including on projects created by
# versions that also copied them to the top level and into ~/.claude/commands.
# Run with: bash tests/test_commands_sync.sh
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=false
# shellcheck source=../lib/project.sh
source "$SCRIPT_DIR/../lib/project.sh"

TESTS_RUN=0
TESTS_PASSED=0

check() {
    local name="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS  %s\n' "$name"
    else
        printf 'FAIL  %s\n      expected: [%s]\n      actual:   [%s]\n' "$name" "$expected" "$actual"
    fi
}

listing() {
    (cd "$1" && find . -type f | sort | tr '\n' ' ')
}

# pwd -P: macOS temp dirs sit behind a /var -> /private/var symlink
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

CLAUDEBOX_SCRIPT_DIR="$TMP/install"
HOME="$TMP/home"
mkdir -p "$CLAUDEBOX_SCRIPT_DIR/commands/pack" "$HOME/.claude/commands"
printf 'bundled a\n' > "$CLAUDEBOX_SCRIPT_DIR/commands/a.md"
printf 'bundled b\n' > "$CLAUDEBOX_SCRIPT_DIR/commands/pack/b.md"

# Host commands dir as an older version left it: bundled copies plus the
# user's own command and one bundled command the user has edited.
cp "$CLAUDEBOX_SCRIPT_DIR/commands/a.md" "$HOME/.claude/commands/a.md"
printf 'mine\n' > "$HOME/.claude/commands/mine.md"

fresh="$TMP/fresh"
mkdir -p "$fresh"
sync_commands_to_project "$fresh"
check "fresh project: bundled once under cbox/, user files without bundled copies" \
    "./cbox/a.md ./cbox/pack/b.md ./user/mine.md " "$(listing "$fresh/commands")"

legacy="$TMP/legacy"
mkdir -p "$legacy"
sync_commands_to_project "$legacy"
cp "$CLAUDEBOX_SCRIPT_DIR/commands/a.md" "$legacy/commands/a.md"
mkdir -p "$legacy/commands/pack"
cp "$CLAUDEBOX_SCRIPT_DIR/commands/pack/b.md" "$legacy/commands/pack/b.md"
printf 'imported\n' > "$legacy/commands/imported.md"
sync_commands_to_project "$legacy"
check "legacy project: top-level bundled copies are pruned, other files kept" \
    "./cbox/a.md ./cbox/pack/b.md ./imported.md ./user/mine.md " "$(listing "$legacy/commands")"
check "legacy project: emptied bundled subdirectory is removed" "gone" \
    "$(if [ -d "$legacy/commands/pack" ]; then printf 'present'; else printf 'gone'; fi)"

printf 'edited by user\n' > "$legacy/commands/a.md"
printf 'edited by user\n' > "$HOME/.claude/commands/a.md"
sync_commands_to_project "$legacy"
check "a bundled command the user edited is kept in both places" \
    "./a.md ./cbox/a.md ./cbox/pack/b.md ./imported.md ./user/a.md ./user/mine.md " "$(listing "$legacy/commands")"

printf 'bundled a v2\n' > "$CLAUDEBOX_SCRIPT_DIR/commands/a.md"
cp "$CLAUDEBOX_SCRIPT_DIR/commands/a.md" "$HOME/.claude/commands/a.md"
rm "$legacy/commands/a.md"
sync_commands_to_project "$legacy"
check "user copy that matches the bundled file again is dropped on resync" \
    "./cbox/a.md ./cbox/pack/b.md ./imported.md ./user/mine.md " "$(listing "$legacy/commands")"

printf '\n%s/%s passed\n' "$TESTS_PASSED" "$TESTS_RUN"
[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]
