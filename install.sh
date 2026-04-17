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
    for pkg in iptables dbus-user-session; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        printf '\n'
        warn "Missing system packages. Ask your admin to run:"
        printf '\n'
        printf '  sudo apt-get install %s\n' "${missing_pkgs[*]}"
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
        printf '  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 %s\n' "$user"
        printf '\n'
        die "Cannot continue without subordinate UID/GID ranges."
    fi
    if ! grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        printf '\n'
        warn "No subordinate GID range for $user. Ask your admin to run:"
        printf '\n'
        printf '  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 %s\n' "$user"
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
    local shell_rc="$HOME/.bashrc"
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "zsh" ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    local needs_update=false

    if ! grep -q 'DOCKER_HOST=unix:///run/user/' "$shell_rc" 2>/dev/null; then
        needs_update=true
    fi

    if [[ "$needs_update" == "true" ]]; then
        log "Adding rootless Docker config to ${shell_rc}"
        cat >> "$shell_rc" << 'SHELL_EOF'

# --- Rootless Docker (added by install-claudebox.sh) ---
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
SHELL_EOF
        log "Shell config updated. Source ${shell_rc} or open a new terminal"
    else
        log "Shell already configured for rootless Docker"
    fi

    # Export for current session so the rest of the script works
    export PATH="$HOME/bin:$PATH"
    export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
}

# ------------------------------------------------ install claudebox from fork --
install_claudebox() {
    log "Installing ClaudeBox from ${CLAUDEBOX_REPO}"

    local tmp_dir=""
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir:-}"' EXIT

    git clone --depth 1 --branch "$CLAUDEBOX_BRANCH" "$CLAUDEBOX_REPO" "$tmp_dir/claudebox"

    cd "$tmp_dir/claudebox"

    # Build the .run installer
    log "Building ClaudeBox installer"
    bash .builder/build.sh

    # Run the installer
    log "Running ClaudeBox installer"
    bash dist/claudebox.run

    cd -
    log "ClaudeBox installed to ${INSTALL_DIR}"
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

# --------------------------------------------------------------------- main --
main() {
    printf '\n'
    log "ClaudeBox + Rootless Docker Installer (Debian 12)"
    printf '\n'

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
