#!/usr/bin/env bash
# Core Commands - Essential ClaudeBox operations
# ============================================================================
# Commands: help, shell, update
# These are the fundamental commands that users interact with most

# Show help function
_cmd_help() {
    # Set up IMAGE_NAME if we're in a project directory
    if [[ -n "${PROJECT_DIR:-}" ]]; then
        # Initialize project directory to ensure parent exists
        init_project_dir "$PROJECT_DIR"
        IMAGE_NAME=$(get_image_name 2>/dev/null || echo "")
    fi
    
    # Check for subcommands
    local subcommand="${1:-}"
    
    case "$subcommand" in
        "full")
            show_full_help
            ;;
        "claude")
            show_claude_help
            ;;
        "")
            # Default behavior - check if we have project and show appropriate help
            local project_folder_name
            project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")
            
            if [[ "$project_folder_name" != "NONE" ]] && [[ -n "${IMAGE_NAME:-}" ]] && docker image inspect "$IMAGE_NAME" &>/dev/null; then
                # In project directory with image - show Claude help
                show_claude_help
            else
                # Not in project directory - show ClaudeBox help
                show_help
            fi
            ;;
        *)
            # Unknown subcommand - show regular help
            show_help
            ;;
    esac
    
    exit 0
}

_cmd_shell() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] _cmd_shell called with args: $*" >&2
    fi
    
    # Set up slot variables if not already set
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        local project_folder_name
        project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")
        
        if [[ "$project_folder_name" == "NONE" ]]; then
            show_no_slots_menu  # This will exit
        fi
        
        IMAGE_NAME=$(get_image_name)
        PROJECT_SLOT_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
        export PROJECT_SLOT_DIR
    fi
    
    # Check if image exists
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project.\nRun 'claudebox' first to build the image."
    fi
    
    local persist_mode=false
    local shell_flags=()
    
    # Check if first arg is "admin"
    if [[ "${1:-}" == "admin" ]]; then
        persist_mode=true
        shift
        # In admin mode, automatically enable sudo and disable firewall
        shell_flags+=("--enable-sudo" "--disable-firewall")
    fi
    
    # Process remaining flags (only for non-persist mode)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable-sudo|--disable-firewall)
                if [[ "$persist_mode" == "false" ]]; then
                    shell_flags+=("$1")
                fi
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Run container for shell
    if [[ "$persist_mode" == "true" ]]; then
        cecho "Administration Mode" "$YELLOW"
        echo "Sudo enabled, firewall disabled."
        echo "Changes will be saved to the image when you exit."
        echo
        
        # Create a named container for admin mode so we can commit it
        local temp_container="claudebox-admin-$$"
        
        # Ensure cleanup runs on any exit (including Ctrl-C)
        cleanup_admin() {
            docker commit "$temp_container" "$IMAGE_NAME" >/dev/null 2>&1
            docker rm -f "$temp_container" >/dev/null 2>&1
        }
        trap cleanup_admin EXIT
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Running admin container with flags: ${shell_flags[*]}" >&2
            echo "[DEBUG] Remaining args after processing: $*" >&2
        fi
        # Don't pass any remaining arguments - only shell and the flags
        run_claudebox_container "$temp_container" "interactive" shell "${shell_flags[@]}"
        
        # Commit changes back to image
        fillbar
        docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
        docker rm -f "$temp_container" >/dev/null 2>&1
        fillbar stop
        success "Changes saved to image!"
    else
        # Regular shell mode - just run without committing
        run_claudebox_container "" "interactive" shell "${shell_flags[@]}"
    fi
    
    exit 0
}

_cmd_update() {
    # "update all" used to download the single-file launcher from upstream
    # RchGrav/claudebox, overwriting this fork's installed script. The fork
    # is a git checkout — update it with git instead.
    if [[ "${1:-}" == "all" ]]; then
        warn "'update all' is disabled in this fork: it would overwrite the launcher with upstream's script."
        info "Update the launcher with: git -C $SCRIPT_DIR pull"
        shift
    fi

    # The project image must exist — the update is applied by rebuilding it.
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found for this project folder: $PROJECT_DIR\nRun 'claudebox' first to build the image, or cd to your project directory."
    fi

    # Updating inside a container cannot stick: containers are ephemeral and
    # Claude lives on image filesystem (~/.nvm), so anything installed there
    # dies with the slot. The only state that persists is the image itself —
    # so pin the target version and rebuild. The pin layer sits above the
    # profile layers in Dockerfile.project, keeping the rebuild cheap.
    local target_version="${1:-}"
    if [[ -z "$target_version" ]]; then
        local registry_url="https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
        local registry_json=""
        if command -v curl >/dev/null 2>&1; then
            registry_json=$(curl -fsSL "$registry_url" 2>/dev/null) || true
        elif command -v wget >/dev/null 2>&1; then
            registry_json=$(wget -qO- "$registry_url" 2>/dev/null) || true
        else
            error "Neither curl nor wget found"
        fi
        if [[ -n "$registry_json" ]]; then
            target_version=$(printf '%s' "$registry_json" \
                | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
                | head -n 1 \
                | sed 's/.*"\([^"]*\)"$/\1/')
        fi
    fi

    case "$target_version" in
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) error "Could not resolve a Claude Code version (got '${target_version:-nothing}').\nCheck access to registry.npmjs.org or pass one explicitly: claudebox update <version>" ;;
    esac

    local pin_file="$HOME/.claudebox/claude-code-version"
    local previous_pin=""
    if [[ -f "$pin_file" ]]; then
        previous_pin=$(head -n 1 "$pin_file")
    fi

    printf '%s\n' "$target_version" > "$pin_file"
    if [[ "$target_version" == "$previous_pin" ]]; then
        info "Claude Code already pinned at $target_version — rebuilding so the image matches"
    else
        info "Pinning Claude Code $target_version"
    fi

    # Rebuild this project's image now. Other projects pick the pin up on
    # their next launch — the pin file is part of the layer checksums.
    build_docker_image

    success "✓ $IMAGE_NAME now carries Claude Code $target_version (other projects update on their next launch)"
    exit 0
}

export -f _cmd_help _cmd_shell _cmd_update