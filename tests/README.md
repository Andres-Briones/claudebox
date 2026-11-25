# ClaudeBox Tests

This directory contains test scripts to verify ClaudeBox compatibility across different Bash versions.

## Test Scripts

### test_bash32_compat.sh
A comprehensive test suite that verifies Bash 3.2 compatibility by checking:
- All profile functions work correctly
- Usage patterns from the main script
- No Bash 4+ specific syntax is used
- Everything works with `set -u` (strict mode)

**Usage:**
```bash
cd tests
./test_bash32_compat.sh
```

### test_in_bash32_docker.sh
Runs the compatibility test suite in actual Bash 3.2 using Docker, then compares with your local Bash version.

**Requirements:** Docker must be installed

**Usage:**
```bash
cd tests
./test_in_bash32_docker.sh
```

## Test Coverage

The test suite covers:

1. **Profile Functions**
   - `get_profile_packages()`
   - `get_profile_description()`
   - `get_all_profile_names()`
   - `profile_exists()`

2. **Usage Patterns**
   - Profile listing (as used in `claudebox profiles`)
   - Dockerfile generation patterns
   - Empty profile handling
   - Invalid profile handling

3. **Bash 3.2 Compatibility**
   - No associative arrays (`declare -A`)
   - No `${var^^}` uppercase expansion
   - No `[[ -v` variable checking
   - Works with `set -u` (strict mode)

## Expected Results

All 13 tests should pass in both Bash 3.2 and modern Bash versions.

## macOS Testing

These tests are particularly important for macOS users, as macOS ships with Bash 3.2 by default. The Docker test ensures compatibility without needing access to a Mac.
### test_commands_sync.sh
Checks that bundled slash commands reach a project exactly once (under `cbox/`), and that copies left at the top level or in `~/.claude/commands` by older versions are pruned without touching the user's own commands.

**Usage:**
```bash
bash tests/test_commands_sync.sh
```
