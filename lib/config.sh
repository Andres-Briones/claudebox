#!/usr/bin/env bash
# Configuration management including INI files and profile definitions.

# -------- INI file helpers ----------------------------------------------------
_read_ini() {               # $1=file $2=section $3=key
  awk -F' *= *' -v s="[$2]" -v k="$3" '
    $0==s {in=1; next}
    /^\[/ {in=0}
    in && $1==k {print $2; exit}
  ' "$1" 2>/dev/null
}

# -------- First-run bootstrap of ~/.claudebox/env -----------------------------
# Creates the env file from examples/env.example if absent. Best-effort fills
# in git identity (GIT_AUTHOR_*, GIT_COMMITTER_*, EMAIL) from the host's
# `git config --global` so containers can commit as you out of the box.
# Idempotent: never touches an existing env file.
bootstrap_env_file() {
    local env_file="${CLAUDEBOX_HOME}/env"
    local example_file="${CLAUDEBOX_SCRIPT_DIR}/examples/env.example"

    [[ -f "$env_file" ]] && return 0
    [[ -f "$example_file" ]] || return 0

    mkdir -p "${CLAUDEBOX_HOME}"
    cp "$example_file" "$env_file"

    local host_name host_email
    host_name="$(git config --global --get user.name 2>/dev/null || true)"
    host_email="$(git config --global --get user.email 2>/dev/null || true)"

    if [[ -n "$host_name" ]] && [[ -n "$host_email" ]]; then
        local tmp
        tmp="$(mktemp "${env_file}.XXXXXX")"
        awk -v name="$host_name" -v email="$host_email" '
            /^# GIT_AUTHOR_NAME=/     { print "GIT_AUTHOR_NAME=" name; next }
            /^# GIT_AUTHOR_EMAIL=/    { print "GIT_AUTHOR_EMAIL=" email; next }
            /^# GIT_COMMITTER_NAME=/  { print "GIT_COMMITTER_NAME=" name; next }
            /^# GIT_COMMITTER_EMAIL=/ { print "GIT_COMMITTER_EMAIL=" email; next }
            /^# EMAIL=/               { print "EMAIL=" email; next }
            { print }
        ' "$env_file" > "$tmp" && mv "$tmp" "$env_file"
        printf 'Created %s with git identity from host gitconfig.\n' "$env_file" >&2
    else
        printf 'Created %s from env.example. Edit to add git identity.\n' "$env_file" >&2
    fi
}


# -------- Profile functions (Bash 3.2 compatible) -----------------------------
get_profile_packages() {
    case "$1" in
        core) echo "gcc g++ make git pkg-config libssl-dev libffi-dev zlib1g-dev tmux" ;;
        build-tools) echo "cmake ninja-build autoconf automake libtool" ;;
        shell) echo "rsync openssh-client man-db gnupg2 aggregate file" ;;
        networking) echo "iptables ipset iproute2 dnsutils" ;;
        c) echo "gdb valgrind clang clang-format clang-tidy cppcheck doxygen libboost-all-dev libcmocka-dev libcmocka0 lcov libncurses5-dev libncursesw5-dev" ;;
        openwrt) echo "rsync libncurses5-dev zlib1g-dev gawk gettext xsltproc libelf-dev ccache subversion swig time qemu-system-arm qemu-system-aarch64 qemu-system-mips qemu-system-x86 qemu-utils" ;;
        rust) echo "" ;;  # Rust installed via rustup
        python) echo "python3 python3-full python3-venv" ;;
        go) echo "" ;;  # Installed from tarball
        flutter) echo "" ;;  # Installed from source
        javascript) echo "" ;;  # Installed via nvm
        bun) echo "" ;;  # Installed via curl installer
        java) echo "" ;;  # Java installed via SDKMan, build tools in profile function
        ruby) echo "ruby-full ruby-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev software-properties-common" ;;
        php) echo "php php-cli php-fpm php-mysql php-pgsql php-sqlite3 php-curl php-gd php-mbstring php-xml php-zip composer" ;;
        database) echo "postgresql-client mysql-client sqlite3 redis-tools mongodb-clients" ;;
        devops) echo "docker.io docker-compose ansible awscli" ;;
        web) echo "nginx apache2-utils httpie" ;;
        embedded) echo "gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen" ;;
        datascience) echo "r-base" ;;
        security) echo "nmap tcpdump wireshark-common netcat-openbsd john hashcat hydra" ;;
        ml) echo "" ;;  # Just cmake needed, comes from build-tools now
        latex) echo "" ;;  # Custom install via heredoc
        wolfram) echo "" ;;  # Custom install via heredoc
        wolfram-cloud) echo "" ;;  # Standalone wolframscript
        gsd) echo "" ;;  # get-shit-done-cc installed via npm in get_profile_gsd
        bun) echo "" ;;
        *) echo "" ;;
    esac
}

get_profile_description() {
    case "$1" in
        core) echo "Core Development Utilities (compilers, VCS, shell tools)" ;;
        build-tools) echo "Build Tools (CMake, autotools, Ninja)" ;;
        shell) echo "Optional Shell Tools (fzf, SSH, man, rsync, file)" ;;
        networking) echo "Network Tools (IP stack, DNS, route tools)" ;;
        c) echo "C/C++ Development (debuggers, analyzers, Boost, ncurses, cmocka)" ;;
        openwrt) echo "OpenWRT Development (cross toolchain, QEMU, distro tools)" ;;
        rust) echo "Rust Development (installed via rustup)" ;;
        python) echo "Python Development (managed via uv)" ;;
        go) echo "Go Development (installed from upstream archive)" ;;
        flutter) echo "Flutter Development (installed from fvm)" ;;
        javascript) echo "JavaScript/TypeScript (Node installed via nvm)" ;;
        bun) echo "Bun JavaScript Runtime (installed via official installer)" ;;
        java) echo "Java Development (latest LTS, Maven, Gradle, Ant via SDKMan)" ;;
        ruby) echo "Ruby Development (gems, native deps, XML/YAML)" ;;
        php) echo "PHP Development (PHP + extensions + Composer)" ;;
        database) echo "Database Tools (clients for major databases)" ;;
        devops) echo "DevOps Tools (Docker, Kubernetes, Terraform, etc.)" ;;
        web) echo "Web Dev Tools (nginx, HTTP test clients)" ;;
        embedded) echo "Embedded Dev (ARM toolchain, serial debuggers)" ;;
        datascience) echo "Data Science (Python, Jupyter, R)" ;;
        security) echo "Security Tools (scanners, crackers, packet tools)" ;;
        ml) echo "Machine Learning (build layer only; Python via uv)" ;;
        latex)   echo "LaTeX + Emacs (TeX Live full, Emacs, feynmp-auto for Feynman diagrams)" ;;
        wolfram) echo "Wolfram Engine 14 (Mathematica kernel, wolframscript)" ;;
        wolfram-cloud) echo "Wolfram Cloud (Python wolframclient, cloud computation, no local engine)" ;;
        gsd) echo "GSD (Get Shit Done) workflow CLI - get-shit-done-cc (provides gsd-sdk with full query subcommand); markdown payload installed separately via scripts/gsd-install.sh" ;;
        *) echo "" ;;
    esac
}

get_all_profile_names() {
    echo "core build-tools shell networking c openwrt rust python go flutter javascript bun java ruby php database devops web embedded datascience security ml latex wolfram wolfram-cloud gsd"
}

profile_exists() {
    local profile="$1"
    for p in $(get_all_profile_names); do
        [[ "$p" == "$profile" ]] && return 0
    done
    return 1
}

expand_profile() {
    case "$1" in
        c) echo "core build-tools c" ;;
        openwrt) echo "core build-tools openwrt" ;;
        ml) echo "core build-tools ml" ;;
        rust|go|flutter|python|php|ruby|java|database|devops|web|embedded|datascience|security|javascript)
            echo "core $1"
            ;;
        shell|networking|build-tools|core)
            echo "$1"
            ;;
        latex|wolfram|wolfram-cloud) echo "$1" ;;
        bun) echo "core bun" ;;
        gsd) echo "core javascript gsd" ;;
        *)
            echo "$1"
            ;;
    esac
}

# -------- Profile file management ---------------------------------------------
get_profile_file_path() {
    # Use the parent directory name, not the slot name
    local parent_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local parent_dir="$HOME/.claudebox/projects/$parent_name"
    mkdir -p "$parent_dir"
    echo "$parent_dir/profiles.ini"
}

read_config_value() {
    local config_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$config_file" ]] || return 1

    awk -F ' *= *' -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$config_file"
}

read_profile_section() {
    local profile_file="$1"
    local section="$2"
    local result=()

    if [[ -f "$profile_file" ]] && grep -q "^\[$section\]" "$profile_file"; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^\[.*\]$ ]] && break
            result+=("$line")
        done < <(sed -n "/^\[$section\]/,/^\[/p" "$profile_file" | tail -n +2 | grep -v '^\[')
    fi

    printf '%s\n' "${result[@]}"
}

update_profile_section() {
    local profile_file="$1"
    local section="$2"
    shift 2
    local new_items=("$@")

    local existing_items=()
    readarray -t existing_items < <(read_profile_section "$profile_file" "$section")

    local all_items=()
    for item in "${existing_items[@]}"; do
        [[ -n "$item" ]] && all_items+=("$item")
    done

    for item in "${new_items[@]}"; do
        local found=false
        for existing in "${all_items[@]}"; do
            [[ "$existing" == "$item" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && all_items+=("$item")
    done

    {
        if [[ -f "$profile_file" ]]; then
            awk -v sect="$section" '
                BEGIN { in_section=0; skip_section=0 }
                /^\[/ {
                    if ($0 == "[" sect "]") { skip_section=1; in_section=1 }
                    else { skip_section=0; in_section=0 }
                }
                !skip_section { print }
                /^\[/ && !skip_section && in_section { in_section=0 }
            ' "$profile_file"
        fi

        echo "[$section]"
        for item in "${all_items[@]}"; do
            echo "$item"
        done
        echo ""
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
}

get_current_profiles() {
    local profiles_file="${PROJECT_PARENT_DIR:-$HOME/.claudebox/projects/$(generate_parent_folder_name "$PWD")}/profiles.ini"
    local current_profiles=()
    
    if [[ -f "$profiles_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profiles_file" "profiles")
    fi
    
    printf '%s\n' "${current_profiles[@]}"
}

# -------- Profile installation functions for Docker builds -------------------
get_profile_core() {
    local packages=$(get_profile_packages "core")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_build_tools() {
    local packages=$(get_profile_packages "build-tools")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_shell() {
    local packages=$(get_profile_packages "shell")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_networking() {
    local packages=$(get_profile_packages "networking")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_c() {
    local packages=$(get_profile_packages "c")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_openwrt() {
    local packages=$(get_profile_packages "openwrt")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_rust() {
    cat << 'EOF'
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/claude/.cargo/bin:$PATH"
EOF
}

get_profile_python() {
    local packages=$(get_profile_packages "python")
    {
        if [[ -n "$packages" ]]; then
            printf 'RUN apt-get update && apt-get install -y %s && apt-get clean\n' "$packages"
        fi
        cat << 'EOF'
USER claude
RUN ~/.local/bin/uv python install 3.12 3.11
USER root
EOF
    }
}

get_profile_go() {
    cat << 'EOF'
RUN wget -O go.tar.gz https://golang.org/dl/go1.21.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz
ENV PATH="/usr/local/go/bin:$PATH"
EOF
}

get_profile_flutter() {
    local flutter_version="${FLUTTER_SDK_VERSION:-stable}"
    cat << EOF
USER claude
RUN curl -fsSL https://fvm.app/install.sh | bash
ENV PATH="/usr/local/bin:$PATH"
RUN fvm install $flutter_version
RUN fvm global $flutter_version
ENV PATH="/home/claude/fvm/default/bin:$PATH"
RUN flutter doctor
USER root
EOF
}

get_profile_javascript() {
    cat << 'EOF'
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
ENV NVM_DIR="/home/claude/.nvm"
RUN . $NVM_DIR/nvm.sh && nvm install --lts
USER claude
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g typescript eslint prettier yarn pnpm"
USER root
EOF
}

get_profile_gsd() {
    cat << 'EOF'
USER claude
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g get-shit-done-cc"
USER root
EOF
}

get_profile_bun() {
    cat << 'EOF'
ENV BUN_INSTALL="/home/claude/.bun"
ENV PATH="/home/claude/.bun/bin:$PATH"
USER claude
RUN curl -fsSL https://bun.sh/install | bash
RUN bun --version
USER root
EOF
}

get_profile_java() {
    cat << 'EOF'
USER claude
RUN curl -s "https://get.sdkman.io?ci=true" | bash
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install java && sdk install maven && sdk install gradle && sdk install ant"
USER root
# Create symlinks for all Java tools in system PATH
RUN for tool in java javac jar jshell; do \
        ln -sf /home/claude/.sdkman/candidates/java/current/bin/$tool /usr/local/bin/$tool; \
    done && \
    ln -sf /home/claude/.sdkman/candidates/maven/current/bin/mvn /usr/local/bin/mvn && \
    ln -sf /home/claude/.sdkman/candidates/gradle/current/bin/gradle /usr/local/bin/gradle && \
    ln -sf /home/claude/.sdkman/candidates/ant/current/bin/ant /usr/local/bin/ant
# Set JAVA_HOME environment variable
ENV JAVA_HOME="/home/claude/.sdkman/candidates/java/current"
ENV PATH="/home/claude/.sdkman/candidates/java/current/bin:$PATH"
EOF
}

get_profile_ruby() {
    local packages=$(get_profile_packages "ruby")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_php() {
    local packages=$(get_profile_packages "php")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_database() {
    local packages=$(get_profile_packages "database")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_devops() {
    # kubectl, helm, terraform are not in Debian apt — installed from upstream
    # repos / installers below. docker.io / docker-compose / ansible / awscli
    # come from Debian.
    cat << 'EOF'
RUN apt-get update && apt-get install -y docker.io docker-compose ansible awscli && apt-get clean

# kubectl from Kubernetes apt repo
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
        gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && apt-get install -y kubectl && apt-get clean

# helm via official installer script
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# terraform from HashiCorp apt repo
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg && \
    chmod 644 /etc/apt/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bookworm main" \
        > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y terraform && apt-get clean
EOF
}

get_profile_web() {
    local packages=$(get_profile_packages "web")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_embedded() {
    local packages=$(get_profile_packages "embedded")
    if [[ -n "$packages" ]]; then
        cat << 'EOF'
RUN apt-get update && apt-get install -y gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen && apt-get clean
USER claude
RUN ~/.local/bin/uv tool install platformio
USER root
EOF
    fi
}

get_profile_datascience() {
    local packages=$(get_profile_packages "datascience")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_security() {
    local packages=$(get_profile_packages "security")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_ml() {
    # ML profile just needs build tools which are dependencies
    echo "# ML profile uses build-tools for compilation"
}

get_profile_latex() {
    cat << 'EOF'
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    emacs-nox texlive-latex-recommended texlive-latex-extra \
    texlive-fonts-recommended texlive-fonts-extra texlive-science \
    texlive-pictures texlive-metapost texlive-bibtex-extra \
    latexmk curl unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN curl -L https://mirrors.ctan.org/macros/latex/contrib/feynmp-auto.zip -o /tmp/feynmp-auto.zip && \
    unzip /tmp/feynmp-auto.zip -d /tmp && \
    INSDIR=$(find /tmp -maxdepth 2 -name "feynmp-auto.ins" | head -1 | xargs dirname) && \
    cd "$INSDIR" && pdflatex -interaction=nonstopmode feynmp-auto.ins && \
    TEXDIR=$(kpsewhich -var-value TEXMFLOCAL)/tex/latex/feynmp-auto && \
    mkdir -p "$TEXDIR" && \
    find /tmp -name "feynmp-auto.sty" -exec cp {} "$TEXDIR/" \; && \
    mktexlsr && \
    rm -rf /tmp/feynmp-auto.zip /tmp/feynmp-auto
EOF
}

get_profile_wolfram() {
    # Installs Wolfram Engine (free tier) for running Mathematica .m scripts.
    # After image build, activate once interactively inside the container:
    #   wolframscript
    # It will prompt for your Wolfram ID (email) and password from your
    # free account at wolfram.com/engine/free-license
    #
    # The installer is downloaded once to ${CLAUDEBOX_HOME}/wolfram/installer/
    # by prepare_wolfram_installer() and copied into the build context, so
    # rebuilds (even --no-cache) don't re-fetch the ~5 GB payload.
    cat << 'EOF'
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xz-utils libfaketime faketime && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY wolfram-installer.sh /tmp/LINUX
RUN chmod +x /tmp/LINUX && \
    /tmp/LINUX -- -auto -execdir=/usr/local/bin -verbose < /dev/null && \
    rm -f /tmp/LINUX
RUN mkdir -p /home/claude/.WolframEngine/Licensing && chown -R claude:claude /home/claude/.WolframEngine
EOF
}

# ---------------------------------------------------------------------------
# Concurrency: portable mkdir-based advisory locks
# ---------------------------------------------------------------------------
# Multiple `claudebox` launches can race on shared resources: the wolfram
# installer download and the shared heavy-base image builds. `mkdir` is
# atomic on POSIX filesystems, so we use it as a lock. Stale locks (whose
# holder process died) are detected via a PID file and cleared automatically.

# Acquire the given lock, blocking up to $timeout seconds. Prints a wait
# message after 5s. Aborts via error() on timeout.
_acquire_lock() {
    local lock_dir="$1"
    local timeout="${2:-1800}"   # default 30 min
    local wait_start
    wait_start=$(date +%s)
    local warned=false

    mkdir -p "$(dirname "$lock_dir")"

    while ! mkdir "$lock_dir" 2>/dev/null; do
        # Stale-lock check: if the recorded PID no longer exists, break in.
        local holder_pid=""
        if [[ -r "$lock_dir/pid" ]]; then
            holder_pid=$(cat "$lock_dir/pid" 2>/dev/null || printf '')
        fi
        if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
            warn "Removing stale lock $lock_dir (holder PID $holder_pid is no longer running)"
            rm -rf "$lock_dir" 2>/dev/null || true
            continue
        fi

        local elapsed=$(( $(date +%s) - wait_start ))
        if [[ $elapsed -ge $timeout ]]; then
            error "Timed out after ${timeout}s waiting for lock $lock_dir. If no other claudebox is running, remove the lock directory manually and retry."
        fi
        if [[ "$warned" == "false" ]] && [[ $elapsed -ge 5 ]]; then
            info "Waiting for another claudebox process (lock: $lock_dir)..."
            warned=true
        fi
        sleep 1
    done

    printf '%s\n' "$$" > "$lock_dir/pid" 2>/dev/null || true
}

# Release the given lock. Safe to call on a lock we don't hold.
_release_lock() {
    local lock_dir="$1"
    rm -rf "$lock_dir" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Heavy profiles — shared base images
# ---------------------------------------------------------------------------
# Some profiles install multi-GB payloads (wolfram engine, texlive). Applying
# them as per-project layers duplicates the payload on disk for every project.
# We instead build one shared "base" image per heavy-profile chain, tag it,
# and have project images FROM the deepest matching chain.
#
# Chain naming: heavies are sorted alphabetically and joined with '+'.
#   heavies=()                 -> claudebox-core           (no chain built)
#   heavies=(latex)            -> claudebox-latex-base
#   heavies=(wolfram)          -> claudebox-wolfram-base
#   heavies=(latex wolfram)    -> claudebox-latex+wolfram-base
#                                  (built FROM claudebox-latex-base)
#
# Each shared base carries a `claudebox.parent=<parent-image-id>` label so we
# can detect when the parent has been rebuilt and the base is stale.

# List of profile names treated as heavy (one per line).
# Extend this list to opt more profiles into shared-base sharing.
_heavy_profile_names() {
    printf '%s\n' latex wolfram
}

# Is $1 a heavy profile? Returns 0 if yes, 1 if no.
is_heavy_profile() {
    local candidate="$1"
    local p
    while IFS= read -r p; do
        if [[ "$p" == "$candidate" ]]; then
            return 0
        fi
    done < <(_heavy_profile_names)
    return 1
}

# Compute the shared-base tag for a sorted list of heavy profiles.
# No args -> claudebox-core.
heavy_chain_tag() {
    if [[ $# -eq 0 ]]; then
        printf 'claudebox-core'
        return 0
    fi
    local joined
    joined=$(IFS='+'; printf '%s' "$*")
    printf 'claudebox-%s-base' "$joined"
}

# Stage any host-cached assets a heavy profile needs into the build context
# before its Dockerfile snippet runs. Called during heavy-base builds.
_prepare_heavy_profile_assets() {
    local profile="$1"
    local build_context="$2"
    case "$profile" in
        wolfram)
            prepare_wolfram_installer "$build_context"
            ;;
        latex)
            : # No cached asset; RUN fetches feynmp-auto from CTAN at build time.
            ;;
    esac
}

# Ensure the full chain of shared-base images exists for a sorted list of
# heavy profiles. Builds each tier lazily. Idempotent.
#   $1        build_context (docker build context path)
#   $2..$N    sorted heavy profile names
ensure_heavy_profile_base_chain() {
    local build_context="$1"
    shift
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local heavies=("$@")
    local parent="claudebox-core"
    local i
    for (( i = 0; i < ${#heavies[@]}; i++ )); do
        local sub_chain=("${heavies[@]:0:$((i + 1))}")
        local tag
        tag=$(heavy_chain_tag "${sub_chain[@]}")
        _ensure_heavy_base_image "$tag" "$parent" "${heavies[$i]}" "$build_context"
        parent="$tag"
    done
}

# Internal: is $tag present with a parent label matching $parent_id?
_heavy_base_up_to_date() {
    local tag="$1"
    local parent_id="$2"
    if ! docker image inspect "$tag" >/dev/null 2>&1; then
        return 1
    fi
    local match
    match=$(docker images \
        --filter "reference=$tag" \
        --filter "label=claudebox.parent=$parent_id" \
        -q 2>/dev/null | head -1)
    [[ -n "$match" ]]
}

# Build one shared-base image if it doesn't exist or its parent has changed.
# Locked so parallel claudebox launches don't both build the same tag.
_ensure_heavy_base_image() {
    local tag="$1"
    local parent="$2"
    local profile="$3"
    local build_context="$4"

    local parent_id
    parent_id=$(docker image inspect --format '{{.Id}}' "$parent" 2>/dev/null || true)
    if [[ -z "$parent_id" ]]; then
        error "$parent not found; cannot build $tag"
    fi

    # Fast path: already up to date, no lock needed.
    if _heavy_base_up_to_date "$tag" "$parent_id"; then
        return 0
    fi

    # Serialize concurrent builders of the same tag.
    local lock_dir="${CLAUDEBOX_HOME}/locks/heavy-base-${tag}.lock"
    _acquire_lock "$lock_dir" 5400   # 90 min: wolfram install can be slow

    # Re-check under the lock: another process may have finished the build
    # while we were waiting.
    if _heavy_base_up_to_date "$tag" "$parent_id"; then
        _release_lock "$lock_dir"
        return 0
    fi

    if docker image inspect "$tag" >/dev/null 2>&1; then
        info "$tag is stale (parent $parent changed); rebuilding"
    fi

    local profile_fn="get_profile_${profile//-/_}"
    if ! type -t "$profile_fn" >/dev/null; then
        _release_lock "$lock_dir"
        error "No profile function $profile_fn for heavy profile $profile"
    fi

    # NOTE: _prepare_heavy_profile_assets writes into the shared build
    # context. That's a separate race from this lock — see notes at the
    # top of the file. In practice wolfram asset staging is itself locked;
    # latex has no host asset.
    _prepare_heavy_profile_assets "$profile" "$build_context"

    local snippet
    snippet=$($profile_fn)

    local base_dockerfile="$build_context/Dockerfile.$tag"
    {
        printf 'FROM %s\n' "$parent"
        printf 'USER root\n'
        printf '%s\n' "$snippet"
    } > "$base_dockerfile"

    info "Building shared base image $tag (one-time; will be reused across projects)..."
    export DOCKER_BUILDKIT=1
    if ! docker build \
        --progress="${BUILDKIT_PROGRESS:-auto}" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --label "claudebox.type=heavy-base" \
        --label "claudebox.profile=$profile" \
        --label "claudebox.parent=$parent_id" \
        -f "$base_dockerfile" -t "$tag" "$build_context"; then
        _release_lock "$lock_dir"
        error "Failed to build shared base image $tag"
    fi

    _release_lock "$lock_dir"
}

# Ensure the Wolfram Engine Linux installer is cached on the host and copied
# into the docker build context so the wolfram profile's Dockerfile snippet
# can COPY it in instead of curl-ing it on every build.
#
# Args:
#   $1  build_context  path passed to `docker build` (installer is placed at
#                      $build_context/wolfram-installer.sh)
prepare_wolfram_installer() {
    local build_context="$1"
    local cache_dir="${CLAUDEBOX_HOME}/wolfram/installer"
    local cached="$cache_dir/WolframEngine-linux.sh"
    local url="https://account.wolfram.com/dl/WolframEngine?platform=Linux"

    mkdir -p "$cache_dir"

    # Lock so parallel claudebox launches don't clobber each other's
    # download of the ~5 GB installer.
    local lock_dir="${CLAUDEBOX_HOME}/locks/wolfram-installer.lock"
    _acquire_lock "$lock_dir" 2700   # 45 min

    # Re-check after acquiring: another process may have finished the download
    # while we were waiting.
    if [[ ! -s "$cached" ]]; then
        info "Downloading Wolfram Engine installer (one-time, cached at $cached)..."
        local tmp="${cached}.part"
        rm -f "$tmp"
        if ! curl -fL --retry 3 -o "$tmp" "$url"; then
            rm -f "$tmp"
            _release_lock "$lock_dir"
            error "Failed to download Wolfram Engine installer from $url"
        fi
        mv -f "$tmp" "$cached"
    fi

    if ! cp "$cached" "$build_context/wolfram-installer.sh"; then
        _release_lock "$lock_dir"
        error "Failed to stage Wolfram installer into build context"
    fi
    chmod +x "$build_context/wolfram-installer.sh"

    _release_lock "$lock_dir"
}

get_profile_wolfram_cloud() {
    # Installs wolframclient Python library for Wolfram Cloud access.
    # No local engine needed — uses Wolfram Cloud for computation.
    # Requires free Wolfram ID (wolfram.com/engine/free-license).
    # Usage:
    #   python -c "from wolframclient.evaluation import WolframCloudSession; ..."
    #   or via wolframscript if installed separately
    cat << 'EOF'
USER claude
RUN ~/.local/bin/uv venv /home/claude/.wolfram-venv && \
    ~/.local/bin/uv pip install --python /home/claude/.wolfram-venv/bin/python wolframclient
USER root
ENV PATH="/home/claude/.wolfram-venv/bin:$PATH"
EOF
}

export -f _read_ini get_profile_packages get_profile_description get_all_profile_names profile_exists expand_profile
export -f get_profile_file_path read_config_value read_profile_section update_profile_section get_current_profiles
export -f get_profile_core get_profile_build_tools get_profile_shell get_profile_networking get_profile_c get_profile_openwrt
export -f get_profile_rust get_profile_python get_profile_go get_profile_flutter get_profile_javascript get_profile_java get_profile_ruby
export -f get_profile_php get_profile_database get_profile_devops get_profile_web get_profile_embedded get_profile_datascience
export -f get_profile_security get_profile_ml get_profile_latex get_profile_wolfram get_profile_wolfram_cloud get_profile_gsd get_profile_bun
export -f prepare_wolfram_installer
export -f _heavy_profile_names is_heavy_profile heavy_chain_tag
export -f _prepare_heavy_profile_assets ensure_heavy_profile_base_chain _ensure_heavy_base_image
export -f _acquire_lock _release_lock _heavy_base_up_to_date