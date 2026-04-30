#!/usr/bin/env bash
# AA-SI workstation setup.
#
# Idempotent and safe to re-run, but designed for a first-time user: the
# voice walks you through what's being set up and why, sets expectations
# for how long things take, and ends with a clear "what to try first."

set -euo pipefail


# ---------------------------------------------------------------------------
# 0. Bootstrap: install `gum` for live spinners and styled output.
# ---------------------------------------------------------------------------

GUM_VERSION="0.14.5"
GUM_DIR="$HOME/.local/bin"
mkdir -p "$GUM_DIR"

PLAIN_MODE=0
if [[ ! -t 1 ]]; then
    PLAIN_MODE=1
elif ! command -v gum >/dev/null 2>&1 && [[ ! -x "$GUM_DIR/gum" ]]; then
    arch=$(uname -m)
    case "$arch" in
        x86_64)  gum_arch="Linux_x86_64" ;;
        aarch64) gum_arch="Linux_arm64" ;;
        *)       gum_arch="" ;;
    esac
    if [[ -n "$gum_arch" ]] \
        && curl -fsSL --connect-timeout 5 \
             "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_${gum_arch}.tar.gz" \
             -o /tmp/gum.tgz 2>/dev/null \
        && tar -xzf /tmp/gum.tgz -C /tmp 2>/dev/null \
        && cp "/tmp/gum_${GUM_VERSION}_${gum_arch}/gum" "$GUM_DIR/gum" 2>/dev/null \
        && chmod +x "$GUM_DIR/gum" 2>/dev/null
    then
        rm -rf "/tmp/gum_${GUM_VERSION}_${gum_arch}" /tmp/gum.tgz
        export PATH="$GUM_DIR:$PATH"
    else
        PLAIN_MODE=1
    fi
fi

if [[ -x "$GUM_DIR/gum" ]] && ! command -v gum >/dev/null 2>&1; then
    export PATH="$GUM_DIR:$PATH"
fi
if ! command -v gum >/dev/null 2>&1; then
    PLAIN_MODE=1
fi


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

banner() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '\n=== %s ===\n\n' "$1"
        return
    fi
    gum style \
        --foreground 51 --bold \
        --border rounded --border-foreground 51 \
        --padding "1 4" --margin "1 0" --align center \
        "$1"
}

# Multi-line styled paragraph (used for the intro and the closing block).
para() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '%s\n' "$@"
        return
    fi
    gum style --foreground 252 --margin "0 0 0 2" "$@"
}

# A section header. Phrased as a full sentence describing the outcome,
# not the command being run.
section() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '\n--- %s ---\n' "$1"
        return
    fi
    gum style --foreground 99 --bold --margin "1 0 0 0" "▸ $1"
}

# Optional one-line note explaining what's about to happen, or how long.
note() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '   %s\n' "$1"
        return
    fi
    gum style --foreground 245 --italic --margin "0 0 0 4" "$1"
}

info()    { _styled "$1" "245"; }
success() { _styled "✓ $1" "84"; }
warn()    { _styled "! $1" "214"; }
problem() { _styled "✗ $1" "203"; }

_styled() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '  %s\n' "$1"
    else
        gum style --foreground "$2" "  $1"
    fi
}


# ---------------------------------------------------------------------------
# Live spinner with elapsed time + tail of command output.
#
# We draw the spinner ourselves with ANSI escape codes (carriage return +
# clear-to-end-of-line) instead of using `gum spin`, because gum's
# --title.file flag isn't available in all versions and we want a single
# code path that works everywhere gum is present.
# ---------------------------------------------------------------------------

# Cursor + line-control escapes.
ESC_HIDE_CURSOR=$'\e[?25l'
ESC_SHOW_CURSOR=$'\e[?25h'
ESC_CLEAR_LINE=$'\r\e[2K'
ESC_DIM=$'\e[2m'
ESC_CYAN=$'\e[36m'
ESC_RESET=$'\e[0m'

spin_pretty() {
    local label="$1"; shift

    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '  ... %s\n' "$label"
        "$@"
        return $?
    fi

    local tmpdir
    tmpdir=$(mktemp -d -t aa-spin-XXXXXX)
    local logfile="$tmpdir/log"

    : >"$logfile"

    # Run the wrapped command in the background.
    ( "$@" >"$logfile" 2>&1 ) &
    local cmdpid=$!

    # Make sure we restore the cursor even if the user Ctrl-C's.
    trap 'printf "%s" "$ESC_SHOW_CURSOR"' INT TERM
    printf '%s' "$ESC_HIDE_CURSOR"

    # Spinner frames (Braille dots, the same set gum uses).
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local frame_count=${#frames[@]}

    local start now elapsed mins secs frame_idx=0 line term_w max_tail
    start=$(date +%s)

    while kill -0 "$cmdpid" 2>/dev/null; do
        now=$(date +%s)
        elapsed=$(( now - start ))
        mins=$(( elapsed / 60 ))
        secs=$(( elapsed % 60 ))

        term_w=$(tput cols 2>/dev/null || echo 100)
        # 4 cols spinner glyph + space, label, " (m:ss)  " ~10 cols, then tail.
        max_tail=$(( term_w - ${#label} - 18 ))
        (( max_tail < 20 )) && max_tail=20

        line=""
        if [[ -s "$logfile" ]]; then
            line=$(tail -c 4000 "$logfile" 2>/dev/null \
                | tr -d '\r' \
                | grep -v '^[[:space:]]*$' \
                | tail -n 1 \
                | tr -dc '[:print:][:space:]' \
                | cut -c1-"$max_tail")
        fi

        # Compose: clear-line + cyan spinner + label + dim "(m:ss)" + dim tail.
        if [[ -n "$line" ]]; then
            printf '%s%s%s%s  %s(%d:%02d)%s  %s%s%s' \
                "$ESC_CLEAR_LINE" \
                "$ESC_CYAN" "${frames[$frame_idx]}" "$ESC_RESET" \
                "$label" \
                "$ESC_DIM" "$mins" "$secs" "$ESC_RESET" \
                "$ESC_DIM" "$line" "$ESC_RESET"
        else
            printf '%s%s%s%s  %s%s(%d:%02d)%s' \
                "$ESC_CLEAR_LINE" \
                "$ESC_CYAN" "${frames[$frame_idx]}" "$ESC_RESET" \
                "$label" \
                "$ESC_DIM" "$mins" "$secs" "$ESC_RESET"
        fi

        frame_idx=$(( (frame_idx + 1) % frame_count ))
        sleep 0.1
    done

    # Wait for the command and capture its real exit code.
    wait "$cmdpid"
    local rc=$?

    # Clear the spinner line, restore cursor, untrap.
    printf '%s%s' "$ESC_CLEAR_LINE" "$ESC_SHOW_CURSOR"
    trap - INT TERM

    # Print a final status line so we have a record of what just ran.
    if [[ $rc -eq 0 ]]; then
        success "$label"
    else
        problem "$label didn't complete (exit $rc). Last lines of output:"
        tail -n 30 "$logfile" | sed 's/^/    /' >&2
    fi

    rm -rf "$tmpdir"
    return $rc
}


# ===========================================================================
# Onboarding starts here.
# ===========================================================================

banner "🐟  Welcome to AA-SI  🌊"

para \
    "AA-SI is NOAA's Active Acoustics Strategic Initiative — a Python toolkit" \
    "for processing fisheries acoustic data (Sv, TS, MVBS, NASC) from Simrad" \
    "EK60 / EK80 echosounders." \
    "" \
    "This script gets your workstation ready: it installs Python, the AA-SI" \
    "tools, and the in-terminal assistant 'aa-help'. Most of it runs unattended." \
    "" \
    "Total time: about 5–10 minutes on a fresh GCP image, faster on re-run." \
    "If a step looks slow, check the line below the spinner — it shows live" \
    "progress so you'll know nothing is hung."

declare -A RESULTS=()


# ---------------------------------------------------------------------------
# 1. Helm-repo cleanup.
# ---------------------------------------------------------------------------

section "Cleaning up stale package sources"
note "Some GCP base images ship with an old Helm repo that fails to update. We remove it if found."

BAD_REPO="https://baltocdn.com/helm/stable/debian"
FOUND_FILES=$(sudo grep -Rl "$BAD_REPO" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)
if [[ -n "$FOUND_FILES" ]]; then
    while IFS= read -r f; do
        info "removing $f"
        sudo rm -f "$f"
    done <<< "$FOUND_FILES"
    RESULTS[stale-sources]="cleaned"
else
    success "nothing to clean — your sources look fine."
    RESULTS[stale-sources]="already clean"
fi


# ---------------------------------------------------------------------------
# 2. System packages.
# ---------------------------------------------------------------------------

section "Refreshing the system"
note "Updating apt indexes and applying any pending OS package upgrades."

spin_pretty "refreshing package lists" sudo apt-get update -qq
spin_pretty "applying available upgrades" sudo apt-get upgrade -y -qq
RESULTS[system-packages]="up to date"


# ---------------------------------------------------------------------------
# 3. Python 3.12 (build from source if not already present).
# ---------------------------------------------------------------------------

section "Setting up Python 3.12"
note "AA-SI tools target Python 3.12. We use the system one if it's there, otherwise build it from source into your home directory."

has_ensurepip() {
    command -v python3.12 >/dev/null 2>&1 \
        && python3.12 -m ensurepip --version >/dev/null 2>&1
}

if has_ensurepip; then
    success "Python 3.12 is already installed at $(command -v python3.12)."
    RESULTS[python]="system"
elif [[ -x "$HOME/python312/bin/python3.12" ]]; then
    success "found a previously-built Python 3.12 in your home directory."
    export PATH="$HOME/python312/bin:$PATH"
    if ! grep -q 'HOME/python312/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/python312/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    RESULTS[python]="reusing prebuilt"
else
    note "Building from source. This is the slow step — about 3–5 minutes. Coffee break time."
    spin_pretty "installing build tools" \
        sudo apt-get install -y -qq build-essential libssl-dev zlib1g-dev \
            libncurses5-dev libncursesw5-dev libreadline-dev libsqlite3-dev \
            libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev \
            tk-dev uuid-dev libffi-dev wget

    BUILD_DIR=$(mktemp -d -t py312-build-XXXXXX)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    pushd "$BUILD_DIR" >/dev/null

    spin_pretty "downloading Python 3.12.3" \
        wget https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz
    spin_pretty "unpacking the source tarball" tar -xzf Python-3.12.3.tgz
    cd Python-3.12.3
    spin_pretty "configuring the build" \
        ./configure --prefix="$HOME/python312" --enable-optimizations
    spin_pretty "compiling Python — the longest step, hang tight" \
        make -j"$(nproc)"
    spin_pretty "installing into ~/python312" make install

    popd >/dev/null
    rm -rf "$BUILD_DIR"
    trap - EXIT

    if ! grep -q 'HOME/python312/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/python312/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/python312/bin:$PATH"
    success "Python 3.12.3 ready in ~/python312."
    RESULTS[python]="built from source"
fi


# ---------------------------------------------------------------------------
# 4. Virtual environment.
# ---------------------------------------------------------------------------

section "Creating your AA-SI virtual environment"
note "Everything AA-SI installs lives in ~/venv312, isolated from system Python. The venv auto-activates from your shell once setup is done."

if [[ ! -d "$HOME/venv312" ]]; then
    spin_pretty "creating the venv" python3.12 -m venv "$HOME/venv312"
    RESULTS[venv]="created"
else
    success "~/venv312 already exists — reusing it."
    RESULTS[venv]="reused"
fi

# shellcheck disable=SC1091
source "$HOME/venv312/bin/activate"
success "venv active. You're now using $(python --version)."


# ---------------------------------------------------------------------------
# 5. /opt payload (placeholder).
# ---------------------------------------------------------------------------

if [[ -d /opt && -n "$(ls -A /opt 2>/dev/null)" ]]; then
    section "Image-baked payload detected"
    note "Some AA-SI images stage extra files in /opt. None enabled in this script — uncomment the cp lines if your image needs them."
fi


# ---------------------------------------------------------------------------
# 6. Knowledge directory + repo prompt aggregation.
# ---------------------------------------------------------------------------

section "Preparing your knowledge directory"
note "~/aa-docs is where you keep notes, manuals, and other reference material that 'aa-help' will search when you ask it questions."

AA_DOCS_HOME="$HOME/aa-docs"
REPO_PROMPTS_DIR="$AA_DOCS_HOME/repo-prompts"
mkdir -p "$AA_DOCS_HOME" "$REPO_PROMPTS_DIR"
success "knowledge directory ready at $AA_DOCS_HOME"

CLONE_STAGE=$(mktemp -d -t aa-clones-XXXXXX)
trap 'rm -rf "$CLONE_STAGE"' EXIT

aggregate_prompts_from_repo() {
    local repo_url="$1"
    local name="$2"
    local clone_dir="$CLONE_STAGE/$name"
    local dest="$REPO_PROMPTS_DIR/$name"

    if ! spin_pretty "fetching $name's prompt files" \
            git clone --depth 1 "$repo_url" "$clone_dir"; then
        warn "couldn't reach $repo_url — skipping its prompts (you can re-run this script later to retry)."
        RESULTS[prompts-$name]="skipped (network)"
        return 0
    fi

    if [[ -d "$clone_dir/docs/prompts" ]]; then
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -r "$clone_dir/docs/prompts/." "$dest/"
        local count
        count=$(find "$dest" -type f | wc -l)
        success "$name: collected $count prompt file(s)"
        RESULTS[prompts-$name]="$count file(s)"
    else
        info "$name has no prompt directory yet — that's fine."
        RESULTS[prompts-$name]="none yet"
    fi
}


# ---------------------------------------------------------------------------
# 7. Install AA-SI Python packages.
# ---------------------------------------------------------------------------

section "Installing AA-SI tools"
note "These are the actual data-processing libraries. Each install pulls fresh source from GitHub, then we cache the docs into your knowledge directory."

spin_pretty "upgrading pip itself" pip install --upgrade pip
spin_pretty "installing common scientific deps (matplotlib, toml, pyworms)" \
    pip install pyworms matplotlib toml

section "Installing aalibrary"
note "The core data-fetch and processing library. Includes the 'aa-*' command-line tools you'll use every day."
spin_pretty "downloading and installing aalibrary" \
    pip install --no-cache-dir --force-reinstall \
        git+https://github.com/nmfs-ost/AA-SI_aalibrary
RESULTS[pkg-aalibrary]="installed"
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_aalibrary" "aalibrary"

section "Installing echoml"
note "K-means and ML utilities for echo classification."
spin_pretty "downloading and installing echoml" \
    pip install --no-cache-dir --force-reinstall \
        git+https://github.com/nmfs-ost/AA-SI_KMeans
RESULTS[pkg-echoml]="installed"
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_KMeans" "echoml"

section "Installing echosms and echoregions"
note "Sister libraries for scattering models and Echoview region handling."
spin_pretty "installing echosms + echoregions" pip install echosms echoregions
RESULTS[pkg-echosms]="installed"


# ---------------------------------------------------------------------------
# 8. Jupyter kernel.
# ---------------------------------------------------------------------------

section "Adding a Jupyter kernel for this venv"
note "This makes 'venv312' selectable as a kernel inside Jupyter / VS Code notebooks."

spin_pretty "installing ipykernel" pip install ipykernel
spin_pretty "registering the venv312 kernel" \
    python -m ipykernel install --user --name=venv312 --display-name "venv312"
RESULTS[jupyter-kernel]="registered"


# ---------------------------------------------------------------------------
# 9. Pre-seed aa-help config.
# ---------------------------------------------------------------------------

section "Configuring aa-help"
note "'aa-help' is a Vertex-AI assistant for the aa-* tools. It reads docs from ~/aa-docs and answers questions in your terminal. We'll write a default config so it works immediately."

AA_HELP_CONFIG_DIR="$HOME/.config/aalibrary"
AA_HELP_CONFIG="$AA_HELP_CONFIG_DIR/aa_help.toml"
mkdir -p "$AA_HELP_CONFIG_DIR"

if [[ ! -f "$AA_HELP_CONFIG" ]]; then
    project_id="${GOOGLE_CLOUD_PROJECT:-}"
    cat > "$AA_HELP_CONFIG" <<TOML
[aa_help]
project_id = "$project_id"
location = "us-central1"
model = "gemini-2.5-flash"
temperature = 0.2
max_output_tokens = 2048
knowledge_dirs = [
  "$AA_DOCS_HOME",
]
extra_system_prompt = ""
rag_top_k = 6
rag_max_chars = 30000
file_scan_root = ""
file_scan_exclude = []
file_index_ttl_seconds = 300
TOML
    if [[ -z "$project_id" ]]; then
        warn "no GCP project ID in your environment — run 'aa-help --setup' once to fill it in."
        RESULTS[aa-help]="config (project ID needed)"
    else
        success "aa-help is configured against project '$project_id'."
        RESULTS[aa-help]="configured"
    fi
else
    success "aa-help already had a config file — leaving your settings alone."
    RESULTS[aa-help]="kept your config"
fi


# ---------------------------------------------------------------------------
# 10. Closing block.
# ===========================================================================

if [[ $PLAIN_MODE -eq 0 ]]; then
    summary_rows=$(printf '%s\n' "${!RESULTS[@]}" | sort | while read -r k; do
        printf '| %-22s | %s |\n' "$k" "${RESULTS[$k]}"
    done)
    summary=$(printf '| %-22s | %s |\n| %s | %s |\n%s' \
        "Step" "Outcome" \
        "----------------------" "------------------------------" \
        "$summary_rows")

    gum style --border rounded --border-foreground 51 --padding "1 2" \
        --margin "2 0 1 0" --foreground 252 \
        "$summary"

    gum style --bold --foreground 51 --margin "1 0" "🎣  You're all set"
    gum style --foreground 252 --margin "0 0 0 2" \
        "Your AA-SI environment is installed and ready. Here's what to do first:" \
        "" \
        "  1.  cd ~                                        # drop into your home dir" \
        "  2.  gcloud auth application-default login       # sign in to GCP for aa-help" \
        "  3.  aa-help --reindex                           # build the local knowledge DB (one-time)" \
        "  4.  aa-help \"what does aa-mvbs do?\"             # try it" \
        "" \
        "Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*'" \
        "commands for actual data processing. 'aa-help --help' lists everything."
    gum style --foreground 245 --margin "1 0" \
        "Knowledge directory:  $AA_DOCS_HOME" \
        "Repo prompts cache:   $REPO_PROMPTS_DIR" \
        "aa-help config:       $AA_HELP_CONFIG"
else
    printf '\n=== Setup summary ===\n\n'
    for k in $(printf '%s\n' "${!RESULTS[@]}" | sort); do
        printf '  %-22s %s\n' "$k" "${RESULTS[$k]}"
    done
    cat <<EOF

You're all set. Here's what to do first:

  1.  cd ~                                        # drop into your home dir
  2.  gcloud auth application-default login       # sign in to GCP for aa-help
  3.  aa-help --reindex                           # build the local knowledge DB
  4.  aa-help "what does aa-mvbs do?"             # try it

Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*' commands
for actual data processing. 'aa-help --help' lists everything.

Knowledge directory:  $AA_DOCS_HOME
Repo prompts cache:   $REPO_PROMPTS_DIR
aa-help config:       $AA_HELP_CONFIG
EOF
fi
