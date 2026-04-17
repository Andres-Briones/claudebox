#!/usr/bin/env bash
# Install rootless Docker and ClaudeBox from fork on Debian 12
set -Eeuo pipefail
IFS=$'\n\t'

readonly CLAUDEBOX_REPO="https://github.com/Andres-Briones/claudebox.git"
readonly CLAUDEBOX_BRANCH="main"
readonly BUILDX_VERSION="v0.21.2"
readonly INSTALL_DIR="$HOME/.claudebox"

# ------------------------------------------------------------------ helpers --
log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "Required command not found: $1"
    fi
}

# ------------------------------------------------------------ distro check --
check_distro() {
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS. This script only supports Debian and Ubuntu."
    fi
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) ;;
        *) die "Unsupported distro: ${ID:-unknown}. This script only supports Debian and Ubuntu." ;;
    esac
}

# -------------------------------------------------------- prerequisite check --
check_prerequisites() {
    log "Checking prerequisites"

    local missing_pkgs=()

    # Commands in the user's PATH
    local -A cmd_to_pkg=(
        [curl]="curl"
        [git]="git"
        [newuidmap]="uidmap"
    )

    for cmd in "${!cmd_to_pkg[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_pkgs+=("${cmd_to_pkg[$cmd]}")
        fi
    done

    # Packages whose binaries live in /usr/sbin (not in regular user PATH)
    # or have no single binary to test — use dpkg-query for reliable status
    for pkg in iptables dbus-user-session fuse-overlayfs; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        printf '\n'
        warn "Missing system packages. Ask your admin to run:"
        printf '\n'
        printf '  apt-get install %s\n' "${missing_pkgs[*]}"
        printf '\n'
        die "Cannot continue without the packages above."
    fi

    # Check subordinate UID/GID ranges
    local user
    user="$(whoami)"
    if ! grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        printf '\n'
        warn "No subordinate UID range for $user. Ask your admin to run:"
        printf '\n'
        printf '  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 %s\n' "$user"
        printf '\n'
        die "Cannot continue without subordinate UID/GID ranges."
    fi
    if ! grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        printf '\n'
        warn "No subordinate GID range for $user. Ask your admin to run:"
        printf '\n'
        printf '  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 %s\n' "$user"
        printf '\n'
        die "Cannot continue without subordinate UID/GID ranges."
    fi

    log "Prerequisites OK"
}

# --------------------------------------------------- install rootless Docker --
install_rootless_docker() {
    if [[ -x "$HOME/bin/dockerd" ]]; then
        log "Rootless Docker already installed at ~/bin/dockerd, skipping download"
    else
        log "Installing rootless Docker"
        curl -fsSL https://get.docker.com/rootless | FORCE_ROOTLESS_INSTALL=1 sh
    fi

    # Use fuse-overlayfs storage driver — overlay2 fails in rootless mode on many
    # filesystems, and vfs copies every layer in full (massive disk usage).
    # fuse-overlayfs gives proper layer sharing in user namespaces.
    local daemon_json="$HOME/.config/docker/daemon.json"
    if [[ ! -f "$daemon_json" ]]; then
        mkdir -p "$HOME/.config/docker"
        printf '{"storage-driver": "fuse-overlayfs"}\n' > "$daemon_json"
        log "Configured fuse-overlayfs storage driver for rootless Docker"
    fi

    # Symlink docker into ~/.local/bin so it's on the same PATH as claudebox
    # (~/bin is rootless Docker's default but isn't always in PATH)
    mkdir -p "$HOME/.local/bin"
    for bin in docker dockerd; do
        if [[ -x "$HOME/bin/$bin" ]] && [[ ! -e "$HOME/.local/bin/$bin" ]]; then
            ln -s "$HOME/bin/$bin" "$HOME/.local/bin/$bin"
        fi
    done

    log "Rootless Docker ready"
}

# ----------------------------------------------------------- install buildx --
install_buildx() {
    local plugin_dir="$HOME/.docker/cli-plugins"
    local buildx_path="${plugin_dir}/docker-buildx"

    if [[ -x "$buildx_path" ]]; then
        log "Docker buildx already installed, skipping"
        return 0
    fi

    log "Installing Docker buildx ${BUILDX_VERSION}"

    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)       die "Unsupported architecture: $arch" ;;
    esac

    mkdir -p "$plugin_dir"
    curl -fsSL \
        "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${arch}" \
        -o "$buildx_path"
    chmod +x "$buildx_path"

    log "Buildx installed"
}

# ------------------------------------------------- configure shell for rootless --
configure_shell() {
    local rc_snippet
    rc_snippet='
# --- Rootless Docker (added by install-claudebox.sh) ---
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"'

    # Detect which shell rc to modify
    local shell_rc="$HOME/.bashrc"
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "zsh" ]]; then
        shell_rc="$HOME/.zshrc"
    fi
    local profile="$HOME/.profile"

    # Collect which files need modification
    local files_to_modify=()
    if ! grep -q 'DOCKER_HOST=unix:///run/user/' "$shell_rc" 2>/dev/null; then
        files_to_modify+=("$shell_rc")
    fi
    if ! grep -q 'DOCKER_HOST=unix:///run/user/' "$profile" 2>/dev/null; then
        files_to_modify+=("$profile")
    fi

    if [[ ${#files_to_modify[@]} -eq 0 ]]; then
        log "Shell already configured for rootless Docker"
        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
        export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
        return 0
    fi

    # Show the user exactly what will be appended and where
    printf '\n'
    warn "The following lines will be appended to these files:"
    for f in "${files_to_modify[@]}"; do
        printf '  - %s\n' "$f"
    done
    printf '\n'
    printf '  %s\n' "# --- Rootless Docker (added by install-claudebox.sh) ---"
    printf '  %s\n' 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'
    printf '  %s\n' 'export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"'
    printf '\n'
    printf 'Proceed? [y/N] '
    read -r response </dev/tty
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        warn "Skipped shell configuration. You will need to add these lines manually."
        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
        export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
        return 0
    fi

    for f in "${files_to_modify[@]}"; do
        log "Appending to ${f}"
        printf '%s\n' "$rc_snippet" >> "$f"
    done

    log "Shell config updated. Log out and back in, or run: source ${shell_rc}"

    # Export for current session so the rest of the script works
    export PATH="$HOME/bin:$PATH"
    export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
}

# ------------------------------------------------ install claudebox from fork --
install_claudebox() {
    local source_dir="$INSTALL_DIR/source"

    if [[ -d "$source_dir/.git" ]]; then
        log "Updating ClaudeBox from ${CLAUDEBOX_REPO}"
        git -C "$source_dir" pull --ff-only
    else
        log "Installing ClaudeBox from ${CLAUDEBOX_REPO}"
        # Remove old non-git install if present
        if [[ -d "$source_dir" ]]; then
            rm -rf "$source_dir"
        fi
        mkdir -p "$INSTALL_DIR"
        git clone --branch "$CLAUDEBOX_BRANCH" "$CLAUDEBOX_REPO" "$source_dir"
    fi

    # Create symlink
    mkdir -p "$HOME/.local/bin"
    ln -sf "$source_dir/main.sh" "$HOME/.local/bin/claudebox"

    # Fix permissions for rootless Docker UID mapping
    # Host UID maps to root inside container, but the container's claude user
    # (UID 1000) maps to a subordinate UID on the host that can't write to
    # host-owned directories. Making projects/ world-writable fixes this.
    mkdir -p "$INSTALL_DIR/projects"
    chmod -R 777 "$INSTALL_DIR/projects"

    log "ClaudeBox installed to ${source_dir}"
}

# ------------------------------------------------------------ verify install --
verify() {
    log "Verifying installation"

    local ok=true

    if command -v docker >/dev/null 2>&1; then
        printf '  docker:    %s\n' "$(docker --version 2>/dev/null || printf 'error')"
    else
        warn "docker not found in PATH"
        ok=false
    fi

    if docker buildx version >/dev/null 2>&1; then
        printf '  buildx:    %s\n' "$(docker buildx version 2>/dev/null)"
    else
        warn "docker buildx not working"
        ok=false
    fi

    if command -v claudebox >/dev/null 2>&1; then
        printf '  claudebox: installed at %s\n' "$(command -v claudebox)"
    elif [[ -x "$HOME/.local/bin/claudebox" ]]; then
        printf '  claudebox: installed at %s\n' "$HOME/.local/bin/claudebox"
    else
        warn "claudebox not found in PATH"
        ok=false
    fi

    if [[ "$ok" == "true" ]]; then
        log "All components verified"
    else
        warn "Some components could not be verified. You may need to open a new terminal."
    fi
}

# ----------------------------------------------------------------- uninstall --
remove_shell_config() {
    local file="$1"
    if [[ -f "$file" ]] && grep -q 'added by install-claudebox.sh' "$file" 2>/dev/null; then
        log "Removing rootless Docker config from ${file}"
        sed -i '/# --- Rootless Docker (added by install-claudebox.sh) ---/,/^export DOCKER_HOST=/d' "$file"
        # Clean up any trailing blank lines left behind
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$file"
    fi
}

remove_rootless_docker() {
    # Clean up Docker data while daemon is still running
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log "Removing all Docker containers, images, and volumes"
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        docker system prune -af --volumes 2>/dev/null || true
    fi

    # Stop daemon and remove systemd units
    if systemctl --user is-active docker >/dev/null 2>&1; then
        log "Stopping rootless Docker daemon"
        systemctl --user stop docker
    fi
    if systemctl --user is-enabled docker >/dev/null 2>&1; then
        systemctl --user disable docker
    fi
    rm -f "$HOME/.config/systemd/user/docker.service"
    rm -f "$HOME/.config/systemd/user/docker.socket"
    rm -f "$HOME/.config/systemd/user/default.target.wants/docker.service"
    rm -f "$HOME/.config/systemd/user/sockets.target.wants/docker.socket"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # Remove binaries from ~/bin
    local docker_bins=(
        docker dockerd dockerd-rootless.sh dockerd-rootless-setuptool.sh
        rootlesskit rootlesskit-docker-proxy
        containerd containerd-shim-runc-v2
        ctr runc vpnkit
        docker-init docker-proxy
        slirp4netns bypass4netns bypass4netnsd
    )
    if [[ -d "$HOME/bin" ]]; then
        log "Removing rootless Docker binaries from ~/bin"
        for bin in "${docker_bins[@]}"; do
            rm -f "$HOME/bin/$bin"
        done
        rmdir "$HOME/bin" 2>/dev/null || true
    fi

    # Remove symlinks
    rm -f "$HOME/.local/bin/docker" "$HOME/.local/bin/dockerd"

    # Remove Docker data
    if [[ -d "$HOME/.local/share/docker" ]]; then
        log "Removing Docker data (~/.local/share/docker) — this may take a moment"
        if command -v rootlesskit >/dev/null 2>&1; then
            rootlesskit rm -rf "$HOME/.local/share/docker"
        elif [[ -x "$HOME/bin/rootlesskit" ]]; then
            "$HOME/bin/rootlesskit" rm -rf "$HOME/.local/share/docker"
        else
            rm -rf "$HOME/.local/share/docker" 2>/dev/null || \
                warn "Could not fully remove ~/.local/share/docker. Remove manually with: rootlesskit rm -rf ~/.local/share/docker"
        fi
    fi

    # Remove Docker config
    if [[ -d "$HOME/.docker" ]]; then
        rm -rf "$HOME/.docker"
    fi
    if [[ -d "$HOME/.config/docker" ]]; then
        rm -rf "$HOME/.config/docker"
    fi

    log "Rootless Docker removed"
}

uninstall() {
    printf '\n'
    log "Uninstalling ClaudeBox"
    printf '\n'

    # 1. Remove ClaudeBox
    if [[ -d "$HOME/.claudebox" ]]; then
        log "Removing ClaudeBox (~/.claudebox)"
        rm -rf "$HOME/.claudebox"
    fi
    rm -f "$HOME/.local/bin/claudebox"

    # 2. Optionally remove Claude CLI config
    if [[ -d "$HOME/.claude" ]]; then
        printf '\n'
        warn "~/.claude contains Claude CLI settings, credentials, and conversation history."
        printf 'Remove ~/.claude? [y/N] '
        read -r response </dev/tty
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log "Removing Claude CLI config (~/.claude)"
            rm -rf "$HOME/.claude"
        else
            log "Keeping ~/.claude"
        fi
    fi

    # 3. Optionally remove rootless Docker
    local has_docker=false
    if [[ -x "$HOME/bin/dockerd" ]] || [[ -d "$HOME/.local/share/docker" ]]; then
        has_docker=true
    fi

    if [[ "$has_docker" == "true" ]]; then
        printf '\n'
        warn "Rootless Docker is installed. This will remove the daemon, all images, containers, and volumes."
        printf 'Also remove rootless Docker? [y/N] '
        read -r response </dev/tty
        if [[ "$response" =~ ^[Yy]$ ]]; then
            remove_rootless_docker
        else
            log "Keeping rootless Docker"
        fi
    fi

    # 4. Remove shell config
    remove_shell_config "$HOME/.bashrc"
    remove_shell_config "$HOME/.zshrc"
    remove_shell_config "$HOME/.profile"

    printf '\n'
    log "Uninstall complete. Log out and back in to clear environment."
    printf '\n'
}

# --------------------------------------------------------------------- main --
main() {
    if [[ "${1:-}" == "--uninstall" ]]; then
        uninstall
        return 0
    fi

    printf '\n'
    log "ClaudeBox + Rootless Docker Installer (Debian/Ubuntu)"
    printf '\n'

    check_distro
    check_prerequisites
    install_rootless_docker
    configure_shell
    install_buildx
    install_claudebox
    verify

    printf '\n'
    log "Done! Open a new terminal, then run: claudebox"
    printf '\n'
}

main "$@"
