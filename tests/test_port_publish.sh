#!/usr/bin/env bash
# Tests for `claudebox --port`: parsing, localhost-by-default binding, validation.
# Run with: bash tests/test_port_publish.sh
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

check "bare port binds to localhost" "127.0.0.1:8080:8080" "$(normalize_port_spec 8080)"
check "host:container mapping binds to localhost" "127.0.0.1:3000:8080" "$(normalize_port_spec 3000:8080)"
check "explicit IP is kept" "0.0.0.0:8080:80" "$(normalize_port_spec 0.0.0.0:8080:80)"

for bad in "" abc 0 70000 "8080:" ":8080" "1.2.3.4::80"; do
    if normalize_port_spec "$bad" >/dev/null 2>&1; then
        check "rejects '$bad'" "rejected" "accepted"
    else
        check "rejects '$bad'" "rejected" "rejected"
    fi
done

parse_cli_args --port 8080 --port=3000:5173 shell --verbose
check "--port is repeatable, both forms" "127.0.0.1:8080:8080 127.0.0.1:3000:5173" "$CLI_PUBLISH_PORTS"
check "--port and its value don't leak to pass-through" "" "${CLI_PASS_THROUGH[*]:-}"
check "other buckets unaffected" "shell|--verbose" "$CLI_SCRIPT_COMMAND|${CLI_HOST_FLAGS[*]}"
check "container ports for the firewall" "8080 5173" "$(published_container_ports)"

parse_cli_args --model opus
check "no --port means nothing published" "" "$CLI_PUBLISH_PORTS"
check "pass-through still works" "--model opus" "${CLI_PASS_THROUGH[*]}"

if (parse_cli_args --port) >/dev/null 2>&1; then
    check "--port without a value fails" "failed" "succeeded"
else
    check "--port without a value fails" "failed" "failed"
fi

printf '\n%s/%s passed\n' "$TESTS_PASSED" "$TESTS_RUN"
[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]
