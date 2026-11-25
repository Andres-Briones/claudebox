#!/usr/bin/env bash
# Unified CLI parser for ClaudeBox
# Implements the four-bucket architecture for clean, predictable CLI handling

# ============================================================================
# CLI PARSER - SINGLE SOURCE OF TRUTH
# ============================================================================

# Four flag buckets (Bash 3.2 compatible - no associative arrays)
readonly HOST_ONLY_FLAGS=(--verbose rebuild)
readonly CONTROL_FLAGS=(--enable-sudo --disable-firewall)
readonly SCRIPT_COMMANDS=(shell create slot slots revoke profiles projects profile info help -h --help add remove install allowlist clean save project tmux kill resume update)

# parse_cli_args - Central CLI parsing with four-bucket architecture
# Usage: parse_cli_args "$@"
# Sets global variables:
#   host_flags: Array of host-only flags (help, version, etc)
#   control_flags: Array of control flags (verbose, enable-sudo, etc)
#   script_command: Single command for ClaudeBox to execute
#   pass_through: Array of args to pass to Claude in container
# Note: Each argument goes into exactly ONE bucket - no duplication
parse_cli_args() {
    local all_args=("$@")
    
    # Initialize bucket arrays
    host_flags=()
    control_flags=()
    script_command=""
    pass_through=()
    publish_ports=""
    extra_mounts=""

    # Single parsing loop - each arg goes into exactly ONE bucket
    local found_script_command=false
    local nargs=${#all_args[@]}
    local i=0
    local arg spec

    while [[ $i -lt $nargs ]]; do
        arg="${all_args[$i]}"
        i=$((i + 1))
        if [[ "$arg" == "--port" ]] || [[ "$arg" == --port=* ]]; then
            # Host-side flag with a value: becomes `docker run -p`, never reaches the container
            if [[ "$arg" == "--port" ]]; then
                spec="${all_args[$i]:-}"
                i=$((i + 1))
            else
                spec="${arg#--port=}"
            fi
            if ! spec=$(normalize_port_spec "$spec"); then
                return 1
            fi
            publish_ports="${publish_ports:+$publish_ports }$spec"
        elif [[ "$arg" == "--mount" ]] || [[ "$arg" == --mount=* ]]; then
            # Host-side flag with a value: becomes `docker run -v`, never reaches the container
            if [[ "$arg" == "--mount" ]]; then
                spec="${all_args[$i]:-}"
                i=$((i + 1))
            else
                spec="${arg#--mount=}"
            fi
            if ! spec=$(normalize_mount_spec "$spec"); then
                return 1
            fi
            # Newline-separated: paths may contain spaces
            extra_mounts="${extra_mounts:+$extra_mounts
}$spec"
        elif [[ " ${HOST_ONLY_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 1: Host-only flags
            host_flags+=("$arg")
        elif [[ " ${CONTROL_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 2: Control flags (pass to container)
            control_flags+=("$arg")
        elif [[ "$found_script_command" == "false" ]] && [[ " ${SCRIPT_COMMANDS[*]} " == *" $arg "* ]]; then
            # Bucket 3: Script commands (first one wins)
            script_command="$arg"
            found_script_command=true
        else
            # Bucket 4: Pass-through (everything else)
            pass_through+=("$arg")
        fi
    done
    
    # Export results for use by main script
    export CLI_HOST_FLAGS=("${host_flags[@]}")
    export CLI_CONTROL_FLAGS=("${control_flags[@]}")
    export CLI_SCRIPT_COMMAND="$script_command"
    export CLI_PASS_THROUGH=("${pass_through[@]}")
    export CLI_PUBLISH_PORTS="$publish_ports"
    export CLI_EXTRA_MOUNTS="$extra_mounts"
}

# normalize_port_spec - Turn a --port value into a `docker run -p` spec.
# Accepts PORT, HOST_PORT:CONTAINER_PORT, or IP:HOST_PORT:CONTAINER_PORT.
# Without an explicit IP the port binds to 127.0.0.1 only: Docker's default of
# 0.0.0.0 would expose the slot to the LAN and bypass host firewalls like ufw.
normalize_port_spec() {
    local spec="$1"
    local ip="127.0.0.1"
    local host_port container_port rest
    case "$spec" in
        *:*:*)
            ip="${spec%%:*}"
            rest="${spec#*:}"
            host_port="${rest%%:*}"
            container_port="${rest#*:}"
            ;;
        *:*)
            host_port="${spec%%:*}"
            container_port="${spec#*:}"
            ;;
        *)
            host_port="$spec"
            container_port="$spec"
            ;;
    esac
    if ! _is_valid_port "$host_port" || ! _is_valid_port "$container_port" || [[ -z "$ip" ]] || [[ "$ip" == *:* ]]; then
        printf "claudebox: invalid --port value '%s' (expected PORT, HOST:CONTAINER or IP:HOST:CONTAINER)\n" "$spec" >&2
        return 1
    fi
    printf '%s:%s:%s\n' "$ip" "$host_port" "$container_port"
}

_is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ $1 -ge 1 ]] && [[ $1 -le 65535 ]]
}

# published_container_ports - Container-side ports of CLI_PUBLISH_PORTS, space-separated
published_container_ports() {
    local spec
    local out=""
    for spec in ${CLI_PUBLISH_PORTS:-}; do
        out="${out:+$out }${spec##*:}"
    done
    printf '%s' "$out"
}

# normalize_mount_spec - Turn a --mount value into a `docker run -v` spec.
# Accepts HOST_PATH or HOST_PATH:CONTAINER_PATH, optionally followed by :ro or :rw.
# Without a container path the mount lands at the same path as on the host, so
# absolute symlinks in the project that point at it resolve inside the slot.
normalize_mount_spec() {
    local spec="$1"
    local mode="rw"
    local host_path container_path parent
    local usage="expected HOST_PATH[:CONTAINER_PATH][:ro]"
    case "$spec" in
        *:ro|*:rw)
            mode="${spec##*:}"
            spec="${spec%:*}"
            ;;
    esac
    case "$spec" in
        *:*:*)
            printf "claudebox: invalid --mount value '%s' (%s)\n" "$1" "$usage" >&2
            return 1
            ;;
        *:*)
            host_path="${spec%%:*}"
            container_path="${spec#*:}"
            ;;
        *)
            host_path="$spec"
            container_path=""
            ;;
    esac
    if [[ -z "$host_path" ]] || [[ "$spec" == *$'\n'* ]]; then
        printf "claudebox: invalid --mount value '%s' (%s)\n" "$1" "$usage" >&2
        return 1
    fi

    # The shell expands ~ in `--mount ~/x` but not in `--mount=~/x`
    case "$host_path" in
        "~") host_path="$HOME" ;;
        "~/"*) host_path="$HOME/${host_path#??}" ;;
    esac
    if [[ "$host_path" != /* ]]; then
        host_path="$PWD/$host_path"
    fi

    # Docker would silently create a missing source as a root-owned directory on the host
    if [[ ! -e "$host_path" ]]; then
        printf "claudebox: --mount path '%s' does not exist on the host\n" "$host_path" >&2
        return 1
    fi
    if [[ -d "$host_path" ]]; then
        if ! host_path=$(cd "$host_path" && pwd); then
            printf "claudebox: --mount path in '%s' is not accessible\n" "$1" >&2
            return 1
        fi
    else
        if ! parent=$(cd "$(dirname "$host_path")" && pwd); then
            printf "claudebox: --mount path in '%s' is not accessible\n" "$1" >&2
            return 1
        fi
        host_path="${parent%/}/$(basename "$host_path")"
    fi

    if [[ -z "$container_path" ]]; then
        container_path="$host_path"
    fi
    if [[ "$container_path" != "/" ]]; then
        container_path="${container_path%/}"
    fi
    if [[ "$container_path" != /* ]]; then
        printf "claudebox: --mount container path '%s' must be absolute\n" "$container_path" >&2
        return 1
    fi
    if [[ "$container_path" == "/" ]] || [[ "$container_path" == "/workspace" ]]; then
        printf "claudebox: --mount can't replace '%s' in the container; pick a target with HOST_PATH:CONTAINER_PATH\n" "$container_path" >&2
        return 1
    fi
    printf '%s:%s:%s\n' "$host_path" "$container_path" "$mode"
}

# Process host-only flags and set environment variables
process_host_flags() {
    for flag in "${CLI_HOST_FLAGS[@]}"; do
        case "$flag" in
            --verbose)
                export VERBOSE=true
                ;;
            rebuild)
                export REBUILD=true
                ;;
            tmux)
                export CLAUDEBOX_WRAP_TMUX=true
                ;;
        esac
    done
}

# Get command requirements - returns one of:
# "none" - pure host command, no Docker or image needed
# "image" - needs image name but not Docker running
# "docker" - needs Docker running and will run container
get_command_requirements() {
    local cmd="${1:-}"
    local subcommand="${2:-}"
    
    case "$cmd" in
        # Pure host commands - no Docker or image needed
        profiles|projects|help|-h|--help|slots|create|revoke|clean|import|unlink|kill|resume)
            echo "none"
            ;;
        # Commands that need image name but not Docker
        info|profile|add|remove|install|allowlist|save)
            echo "image"
            ;;
        # Commands that need Docker and will run containers
        shell|project|rebuild|update|config|mcp|migrate-installer|tmux|slot|"")
            echo "docker"
            ;;
        # Unknown commands are forwarded to Claude in container
        *)
            echo "docker"
            ;;
    esac
}

# Legacy function for compatibility
requires_docker_image() {
    local cmd="${1:-}"
    local req=$(get_command_requirements "$cmd")
    [[ "$req" == "docker" ]]
}

# Check if current command requires a slot
requires_slot() {
    local cmd="${1:-}"
    
    # Commands that need a slot
    case "$cmd" in
        shell|update|config|mcp|migrate-installer|create|slot|"")
            return 0  # true - needs slot
            ;;
        *)
            return 1  # false - doesn't need slot
            ;;
    esac
}

# Debug output for parsed arguments (only if VERBOSE=true)
debug_parsed_args() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[DEBUG] CLI Parser Results:" >&2
        echo "[DEBUG]   Host flags: ${CLI_HOST_FLAGS[*]}" >&2
        echo "[DEBUG]   Control flags: ${CLI_CONTROL_FLAGS[*]}" >&2
        echo "[DEBUG]   Script command: ${CLI_SCRIPT_COMMAND}" >&2
        echo "[DEBUG]   Pass-through: ${CLI_PASS_THROUGH[*]}" >&2
        echo "[DEBUG]   Published ports: ${CLI_PUBLISH_PORTS:-}" >&2
        printf '[DEBUG]   Extra mounts: %s\n' "$(printf '%s' "${CLI_EXTRA_MOUNTS:-}" | tr '\n' ' ')" >&2
    fi
}

# Export all functions
export -f parse_cli_args normalize_port_spec normalize_mount_spec _is_valid_port published_container_ports process_host_flags get_command_requirements requires_docker_image requires_slot debug_parsed_args