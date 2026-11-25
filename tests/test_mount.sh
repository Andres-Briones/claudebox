#!/usr/bin/env bash
# Tests for `claudebox --mount`: parsing, same-path default, validation.
# Run with: bash tests/test_mount.sh
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/cli.sh
source "$SCRIPT_DIR/../lib/cli.sh"

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

check_rejected() {
    local name="$1" spec="$2"
    if normalize_mount_spec "$spec" >/dev/null 2>&1; then
        check "$name" "rejected" "accepted"
    else
        check "$name" "rejected" "rejected"
    fi
}

# pwd -P: macOS temp dirs sit behind a /var -> /private/var symlink
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data" "$TMP/with space" "$TMP/home/notes"
touch "$TMP/data/file.txt"

check "bare path mounts at the same path, read-write" "$TMP/data:$TMP/data:rw" "$(normalize_mount_spec "$TMP/data")"
check "explicit container path" "$TMP/data:/data:rw" "$(normalize_mount_spec "$TMP/data:/data")"
check "read-only with container path" "$TMP/data:/data:ro" "$(normalize_mount_spec "$TMP/data:/data:ro")"
check "read-only without container path" "$TMP/data:$TMP/data:ro" "$(normalize_mount_spec "$TMP/data:ro")"
check "trailing slashes are dropped" "$TMP/data:/data:rw" "$(normalize_mount_spec "$TMP/data/:/data/")"
check "relative path resolves against the current directory" "$TMP/data:$TMP/data:rw" "$(cd "$TMP" && normalize_mount_spec data)"
check "dot segments are normalized" "$TMP/data:$TMP/data:rw" "$(cd "$TMP/data" && normalize_mount_spec ../data)"
check "single file can be mounted" "$TMP/data/file.txt:/f.txt:ro" "$(normalize_mount_spec "$TMP/data/file.txt:/f.txt:ro")"
check "~/ is expanded in the --mount=~/x form" "$TMP/home/notes:$TMP/home/notes:rw" "$(HOME="$TMP/home" normalize_mount_spec '~/notes')"

check_rejected "rejects empty value" ""
check_rejected "rejects missing host path" "$TMP/nope"
check_rejected "rejects relative container path" "$TMP/data:data"
check_rejected "rejects replacing /workspace" "$TMP/data:/workspace"
check_rejected "rejects replacing /" "$TMP/data:/"
check_rejected "rejects too many fields" "$TMP/data:/a:/b"
check_rejected "rejects unknown mode" "$TMP/data:/data:rx"

parse_cli_args --mount "$TMP/with space" --mount="$TMP/data:/data:ro" shell --verbose
check "--mount is repeatable, both forms, spaces survive" \
    "$TMP/with space:$TMP/with space:rw|$TMP/data:/data:ro|" \
    "$(printf '%s' "$CLI_EXTRA_MOUNTS" | tr '\n' '|')|"
check "--mount and its value don't leak to pass-through" "" "${CLI_PASS_THROUGH[*]:-}"
check "other buckets unaffected" "shell|--verbose" "$CLI_SCRIPT_COMMAND|${CLI_HOST_FLAGS[*]}"

parse_cli_args --model opus
check "no --mount means no extra mounts" "" "$CLI_EXTRA_MOUNTS"
check "pass-through still works" "--model opus" "${CLI_PASS_THROUGH[*]}"

if (parse_cli_args --mount) >/dev/null 2>&1; then
    check "--mount without a value fails" "failed" "succeeded"
else
    check "--mount without a value fails" "failed" "failed"
fi

printf '\n%s/%s passed\n' "$TESTS_PASSED" "$TESTS_RUN"
[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]
