#!/usr/bin/env bash
# AA-SI workstation setup.
#
# Idempotent and safe to re-run, but designed for a first-time user: the
# voice walks you through what's being set up and why, sets expectations
# for how long things take, and ends with a clear "what to try first."
#
# This variant assumes the base image already has Python 3.13 installed
# and creates the venv at ~/venv313.

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

# Generic single-line bordered banner. Kept for any future short-title use.
banner() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '\n=== %s ===\n\n' "$1"
        return
    fi
    gum style \
        --foreground 39 --bold \
        --border rounded --border-foreground 39 \
        --padding "1 4" --margin "1 0" --align center \
        "$1"
}

# Welcome banner — wider, multi-line, width-aware. Replaces the single-line
# emoji-driven version, which had two long-running issues:
#   1) electric-cyan (color 51) is hard to read on light terminals
#   2) the leading 🐟 / trailing 🌊 glyphs render as tofu boxes on terminals
#      without an emoji-capable font (common over plain SSH), making the
#      whole banner look "broken"
# This version uses a more neutral blue (color 39), a double-line border,
# and an ASCII-only title with the project description on a second line.
# It also caps content width so the banner doesn't sprawl on wide terminals
# and degrades to a centered un-bordered title on narrow ones.
banner_welcome() {
    if [[ $PLAIN_MODE -eq 1 ]]; then
        printf '\n'
        printf '  ============================================================\n'
        printf '                       AA-SI WORKSTATION\n'
        printf '          NOAA Active Acoustics Strategic Initiative\n'
        printf '  ============================================================\n\n'
        return
    fi

    local term_w content_w
    term_w=$(tput cols 2>/dev/null || echo 80)
    # Cap at 60 cols so the banner stays readable on ultra-wide terminals;
    # shrink to fit on narrow ones, leaving a 6-col margin for the border.
    if (( term_w >= 70 )); then
        content_w=60
    else
        content_w=$(( term_w - 6 ))
    fi
    (( content_w < 36 )) && content_w=36

    if (( term_w >= 50 )); then
        gum style \
            --align center --bold --foreground 39 \
            --border double --border-foreground 39 \
            --padding "1 3" --margin "1 0" \
            --width "$content_w" \
            "AA-SI WORKSTATION SETUP" \
            "" \
            "NOAA Active Acoustics Strategic Initiative"
    else
        # Very narrow terminal — skip the border entirely.
        gum style --align center --bold --foreground 39 --margin "1 0 0 0" \
            "AA-SI WORKSTATION SETUP"
        gum style --align center --foreground 250 --margin "0 0 1 0" \
            "NOAA Active Acoustics Strategic Initiative"
    fi
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
        # Format must have 12 specifiers to match the 12 args. The previous
        # version had 11 — missing the %s for the ESC_DIM that wraps the
        # (m:ss) time — which made printf try to interpret the ESC_DIM
        # escape sequence as an integer for %d ("printf: : invalid number"),
        # visible whenever $line was non-empty.
        if [[ -n "$line" ]]; then
            printf '%s%s%s%s  %s%s(%d:%02d)%s  %s%s%s' \
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

banner_welcome

para \
    "AA-SI is NOAA's Active Acoustics Strategic Initiative — a Python toolkit" \
    "for processing fisheries acoustic data (Sv, TS, MVBS, NASC) from Simrad" \
    "EK60 / EK80 echosounders." \
    "" \
    "This script gets your workstation ready: it installs the AA-SI tools" \
    "and the in-terminal assistant 'aa-help'. Most of it runs unattended." \
    "" \
    "Total time: about 2–4 minutes on a fresh GCP image, faster on re-run." \
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
# 3. Python 3.13 (image-provided).
#
# This image ships with Python 3.13 already installed, so we just verify
# it's present and usable. If `python3.13` isn't on PATH for some reason,
# we bail loudly rather than silently falling back to a different Python
# — the AA-SI stack is pinned to 3.13 in this script.
# ---------------------------------------------------------------------------

section "Verifying Python 3.13 is available"
note "AA-SI tools target Python 3.13. This image ships with it pre-installed; we just confirm it's usable."

if ! command -v python3.13 >/dev/null 2>&1; then
    problem "python3.13 not found on PATH."
    problem "This script expects an image with Python 3.13 already installed."
    problem "If you're on a different image, install Python 3.13 first or use the build-from-source variant of init.sh."
    exit 1
fi

if ! python3.13 -m ensurepip --version >/dev/null 2>&1; then
    problem "python3.13 was found at $(command -v python3.13) but 'ensurepip' isn't available."
    problem "The system Python 3.13 looks incomplete; install python3.13-venv (Debian/Ubuntu) and re-run."
    exit 1
fi

success "Python 3.13 is ready at $(command -v python3.13) ($(python3.13 --version))."
RESULTS[python]="system (pre-installed)"


# ---------------------------------------------------------------------------
# 4. Virtual environment.
# ---------------------------------------------------------------------------

section "Creating your AA-SI virtual environment"
note "Everything AA-SI installs lives in ~/venv313, isolated from system Python. The venv auto-activates from your shell once setup is done."

if [[ ! -d "$HOME/venv313" ]]; then
    spin_pretty "creating the venv" python3.13 -m venv "$HOME/venv313"
    RESULTS[venv]="created"
else
    success "~/venv313 already exists — reusing it."
    RESULTS[venv]="reused"
fi

# shellcheck disable=SC1091
source "$HOME/venv313/bin/activate"
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

section "Installing AA-SI_KMeans"
note "K-means and ML utilities for echo classification."
spin_pretty "downloading and installing AA-SI_KMeans" \
    pip install --no-cache-dir --force-reinstall \
        git+https://github.com/nmfs-ost/AA-SI_KMeans
RESULTS[pkg-echoml]="installed"
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_KMeans" "AA-SI_KMeans"


# ---------------------------------------------------------------------------
# 7a. echosms + echoregions.
#
# echosms: standard PyPI install, no surprises.
#
# echoregions: needs special handling. The 0.2.3 wheel on PyPI has two
# problems we've hit repeatedly in this environment:
#
#   1) The wheel sometimes ships without `_echoregions_version.py`, the
#      version-stub module that `setuptools-scm` is supposed to generate
#      at build time. When that file is missing, `import echoregions`
#      raises ModuleNotFoundError immediately — every aa-* tool that
#      touches echoregions fails before it can do anything.
#
#   2) The 0.2.3 wheel pins `zarr<3` in its metadata. echopype 0.11+
#      requires `zarr>=3` (uses zarr.codecs.BloscCodec, a zarr-3 API).
#      pip cannot satisfy both, so `pip install echoregions` will
#      downgrade zarr and silently break echopype.
#
# Both problems are already fixed on the project's `main` branch but no
# release has been cut yet. So we install from git instead of PyPI:
# building from a git checkout lets setuptools-scm read tags and emit
# the version stub correctly, AND we pick up the loosened `zarr<4` pin.
#
# If git install fails (network, transient build issue), we fall back
# to the PyPI wheel and patch around the version-stub bug if it bites.
# ---------------------------------------------------------------------------

section "Installing echosms and echoregions"
note "Sister libraries for scattering models (echosms) and Echoview region handling (echoregions). echoregions is installed from its GitHub main branch, not PyPI — see the comment above this section in init.sh for why."

spin_pretty "installing echosms (PyPI)" pip install --no-cache-dir echosms
RESULTS[pkg-echosms]="installed"

# These are wrapped in functions so spin_pretty can run them as a single
# command and capture their full output for its tail-of-log display.
_install_echoregions_from_git() {
    pip install --no-cache-dir --force-reinstall \
        "git+https://github.com/OSOceanAcoustics/echoregions.git@main"
}

_verify_echoregions() {
    python -c "import echoregions; print('echoregions', echoregions.__version__)"
}

_write_echoregions_version_stub() {
    # Last-ditch fix for the missing _echoregions_version.py case.
    # We only call this if the import is failing for that specific reason.
    local site_pkgs
    site_pkgs=$(python -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || true)
    if [[ -n "$site_pkgs" && -d "$site_pkgs" ]]; then
        printf 'version = "0.0.0+stub"\n' > "$site_pkgs/_echoregions_version.py"
        return 0
    fi
    return 1
}

if spin_pretty "installing echoregions (git main)" _install_echoregions_from_git \
        && spin_pretty "verifying echoregions import" _verify_echoregions; then
    RESULTS[pkg-echoregions]="installed (git main)"
else
    warn "echoregions via git main didn't work cleanly — trying PyPI fallback."
    if spin_pretty "installing echoregions (PyPI fallback)" \
            pip install --no-cache-dir --force-reinstall echoregions; then
        if ! _verify_echoregions >/dev/null 2>&1; then
            warn "import still failing — writing _echoregions_version stub."
            _write_echoregions_version_stub || true
        fi
        if _verify_echoregions >/dev/null 2>&1; then
            RESULTS[pkg-echoregions]="installed (PyPI + version stub)"
        else
            problem "echoregions cannot be imported. aa-evr will not work until this is fixed manually."
            RESULTS[pkg-echoregions]="FAILED"
        fi
    else
        problem "echoregions failed to install from both git and PyPI."
        RESULTS[pkg-echoregions]="FAILED"
    fi
fi


# ---------------------------------------------------------------------------
# 7b. Pin zarr to >=3.
#
# aalibrary 1.2.0's metadata pins `zarr==2.8.3` (a stale pin from years
# ago). Depending on install order, pip may honor that pin and downgrade
# zarr — which immediately breaks echopype 0.11+, since it imports
# `zarr.codecs.BloscCodec` (a zarr-3 API). Force zarr back to >=3 here,
# AFTER all the AA-SI packages are installed, so whatever transitive
# pin tug-of-war happened above is settled in echopype's favor.
# Pip will print a "dependency conflict" warning about aalibrary's pin;
# that warning is cosmetic — the code works fine.
# ---------------------------------------------------------------------------

section "Pinning zarr to a working version"
note "aalibrary's metadata pins an old zarr; echopype needs zarr>=3. We force zarr>=3 here so echopype imports cleanly. (Pip will warn about the conflict — that warning is cosmetic and safe to ignore.)"
spin_pretty "ensuring zarr>=3 is installed" \
    pip install --no-cache-dir --upgrade "zarr>=3,<4"
RESULTS[zarr-pin]="zarr>=3,<4"


# ---------------------------------------------------------------------------
# 7c. Smoke test: verify the whole stack imports cleanly.
# ---------------------------------------------------------------------------

section "Verifying the AA-SI Python stack"
note "Importing every key library in one shot. If this fails, the rest of the script's output will tell you exactly where to look."

_verify_stack() {
    python - <<'PY'
import sys
mods = ["echopype", "echoregions", "zarr", "aalibrary"]
versions = {}
for m in mods:
    mod = __import__(m)
    versions[m] = getattr(mod, "__version__", "?")
for m, v in versions.items():
    print(f"  {m:<14} {v}")
PY
}

if spin_pretty "importing echopype, echoregions, zarr, aalibrary" _verify_stack; then
    RESULTS[stack-verified]="all imports OK"
else
    problem "Stack verification failed. Check the error above; aa-* tools may not run until it's fixed."
    RESULTS[stack-verified]="FAILED"
fi


# ---------------------------------------------------------------------------
# 8. Jupyter kernel.
# ---------------------------------------------------------------------------

section "Adding a Jupyter kernel for this venv"
note "This makes 'venv313' selectable as a kernel inside Jupyter / VS Code notebooks."

spin_pretty "installing ipykernel" pip install ipykernel
spin_pretty "registering the venv313 kernel" \
    python -m ipykernel install --user --name=venv313 --display-name "venv313"
RESULTS[jupyter-kernel]="registered"


# ---------------------------------------------------------------------------
# 8a. Fetch the Examples notebook.
#
# A worked-examples notebook from AA-SI_GCPSetup that walks through the
# tools we just installed. Dropped in $HOME so it shows up at the top of
# the file tree the first time the user opens Jupyter / VS Code, with no
# digging required.
#
# We pull the *raw* GitHub URL (raw.githubusercontent.com), not the
# blob/main page — the blob URL returns HTML, which would save a useless
# webpage instead of the notebook JSON. Best-effort: a network failure
# warns and continues instead of aborting setup.
# ---------------------------------------------------------------------------

section "Fetching the Examples notebook"
note "Drops Examples.ipynb (from AA-SI_GCPSetup) into your home directory so you have a worked walkthrough of the aa-* tools ready to open in Jupyter."

EXAMPLES_NB_URL="https://raw.githubusercontent.com/nmfs-ost/AA-SI_GCPSetup/main/Examples.ipynb"
EXAMPLES_NB_PATH="$HOME/Examples.ipynb"

_fetch_examples_notebook() {
    curl -fsSL --connect-timeout 10 "$EXAMPLES_NB_URL" -o "$EXAMPLES_NB_PATH"
}

if spin_pretty "downloading Examples.ipynb to $EXAMPLES_NB_PATH" _fetch_examples_notebook; then
    success "Examples.ipynb is at $EXAMPLES_NB_PATH"
    RESULTS[examples-notebook]="downloaded"
else
    warn "couldn't download Examples.ipynb. You can fetch it manually from $EXAMPLES_NB_URL"
    RESULTS[examples-notebook]="skipped (network)"
fi


# ---------------------------------------------------------------------------
# 9. Jupyter ↔ aa-* startup glue.
#
# Two tiny IPython startup files so the aa-* tools work cleanly inside
# any Jupyter / VS Code notebook, in any environment, without per-cell
# boilerplate:
#
#   00-aa-path.py   prepends the kernel's own bin/ to PATH so that
#                   `!aa-sv`, `!aa-graph`, etc. resolve correctly even
#                   when Jupyter itself was launched from a different
#                   environment than the kernel.
#
#   01-aa-show.py   defines `aa_show()` globally — a one-liner helper
#                   that takes the captured output of `!!cmd`, grabs
#                   the artifact path (always the last stdout line per
#                   the aa-pipeline contract), and renders it inline
#                   if it's an image.
#
# These live under ~/.ipython/profile_default/startup/ which IPython
# loads automatically at the start of every kernel — so they apply to
# the venv313 kernel registered above and to any other kernel the user
# adds later.
# ---------------------------------------------------------------------------

section "Wiring Jupyter notebooks to the aa-* pipeline"
note "Drops two IPython startup files so '!aa-graph' finds your tools and 'aa_show(!!aa-graph file.nc)' renders the result inline. No notebook setup cells needed."

IPYTHON_STARTUP_DIR="$HOME/.ipython/profile_default/startup"
mkdir -p "$IPYTHON_STARTUP_DIR"

# 00-aa-path.py — fix `!aa-*` lookup inside Jupyter.
cat > "$IPYTHON_STARTUP_DIR/00-aa-path.py" <<'PYEOF'
"""Auto-prepend the kernel's own bin/ to PATH so `!cmd` finds tools
installed alongside the kernel's Python (e.g. aa-sv, aa-graph, etc.).

Without this, `!aa-sv` in a Jupyter cell fails with 'command not found'
when Jupyter itself was launched from a different env than the kernel
(extremely common: jupyter installed in base, kernel pointing at a venv).

Generated by AA-SI init.sh — re-running setup will overwrite this file.
"""
import os
import sys

_bin = os.path.dirname(sys.executable)
if _bin not in os.environ.get("PATH", "").split(os.pathsep):
    os.environ["PATH"] = _bin + os.pathsep + os.environ.get("PATH", "")
PYEOF
success "wrote $IPYTHON_STARTUP_DIR/00-aa-path.py  (PATH fix)"

# 01-aa-show.py — define aa_show() for inline pipeline output.
cat > "$IPYTHON_STARTUP_DIR/01-aa-show.py" <<'PYEOF'
"""Render the artifact produced by an aa-* pipeline inline.

Two ways to call:

    aa_show("aa-sv input.raw | aa-graph")
        Pass the pipeline as a string. aa_show runs it itself, then
        renders the last stdout line. Works with arbitrary pipes.

    out = !!aa-sv input.raw | aa-graph
    aa_show(out)
        Pass the captured output of !!cmd. The two-line form is the
        safe escape hatch when you're assembling a command from variables.

Why two forms? IPython's `!!cmd` shorthand is *only* recognized at
the top of a line or as the right-hand side of an assignment — NOT
inside function call arguments. So `aa_show(!!cmd)` raises SyntaxError.
Passing a string sidesteps that entirely.

The last stdout line of any aa-* tool is the artifact path (that's the
pipeline contract). aa_show grabs that last line and either displays
it inline (PNG/JPG/GIF) or prints it. The path is also returned so you
can chain further work in Python:

    png = aa_show("aa-sv input.raw | aa-graph")
    # png is now '/abs/path/to/file_Sv_graph.png'

Generated by AA-SI init.sh — re-running setup will overwrite this file.
"""
import os
import subprocess
import sys
from IPython.display import Image, display


def aa_show(arg):
    if isinstance(arg, str):
        # Run via subprocess so we keep stdout (= artifact path) and
        # stderr (= loguru noise) separate. ip.getoutput() merges them,
        # which lets a log line masquerade as the artifact path
        # whenever a pipeline stage fails.
        env = {**os.environ}
        # Match what !!cmd would have done: prepend the kernel's bin/
        # so tools installed in the kernel's env are found first.
        env["PATH"] = (
            os.path.dirname(sys.executable) + os.pathsep + env.get("PATH", "")
        )
        result = subprocess.run(
            arg,
            shell=True,
            executable="/bin/bash",
            capture_output=True,
            text=True,
            env=env,
        )
        if result.returncode != 0:
            print(f"aa_show: pipeline exited {result.returncode}.\n")
            if result.stderr.strip():
                print("--- stderr ---")
                print(result.stderr.rstrip())
            if result.stdout.strip():
                print("\n--- stdout ---")
                print(result.stdout.rstrip())
            return None
        out = result.stdout.splitlines()
    else:
        out = list(arg) if arg is not None else []

    # Drop blank trailing lines so out[-1] is the real last line.
    while out and not out[-1].strip():
        out.pop()

    if not out:
        print("(no output)")
        return None

    path = out[-1].strip()
    if path.endswith((".png", ".jpg", ".jpeg", ".gif")):
        display(Image(path))
    elif os.path.exists(path):
        print(path)
    else:
        # Last line isn't a file — pipeline probably succeeded but
        # didn't follow the "print artifact path on stdout" contract.
        # Show what we got so the user can debug.
        print("(last stdout line is not a file path — full stdout below)")
        print("\n".join(out))
        return None
    return path
PYEOF
success "wrote $IPYTHON_STARTUP_DIR/01-aa-show.py  (aa_show helper)"

RESULTS[jupyter-startup]="2 files installed"


# ---------------------------------------------------------------------------
# 10. Pre-seed aa-help config.
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
# 11. Authenticate with GCP and fetch a sample raw acoustic data file.
#
# The aa-raw fetch path reads from a Google Cloud bucket, so it needs
# Application Default Credentials in place before it can talk to NCEI.
# We run `gcloud auth application-default login` here — interactively;
# it will print a URL for the user to visit and paste a verification
# code back. Once that returns, we pull a known-good EK60 .raw file
# from the Henry B. Bigelow HB0905 survey so the user has real data to
# point the rest of the aa-* tools at.
#
# Both steps are best-effort: if auth or the fetch fails (user aborted,
# network, NCEI hiccup) we warn and continue rather than aborting the
# whole setup. `|| true` keeps `set -e` from killing us.
# ---------------------------------------------------------------------------

section "Authenticating with GCP"
note "'gcloud auth application-default login' opens an auth flow in your browser (or prints a URL to visit). Sign in with your Google account so 'aa-raw' and 'aa-help' can read from GCP. This is interactive — follow the prompts."

# Don't wrap this in spin_pretty: the command is interactive and prints
# a URL the user has to visit. Capturing its output would hide that.
if gcloud auth application-default login; then
    success "GCP application-default credentials are in place."
    RESULTS[gcp-auth]="authenticated"
else
    warn "auth didn't complete cleanly. You can re-run 'gcloud auth application-default login' yourself later; aa-raw and aa-help will fail until you do."
    RESULTS[gcp-auth]="skipped"
fi

section "Fetching a sample EK60 .raw file"
note "Pulls one file from the Bigelow HB0905 survey via 'aa-raw' so you have real data to try the tools against. Best-effort — a failure here won't stop setup."

_fetch_sample_raw() {
    aa-raw --file_name D20090916-T132105.raw \
           --ship_name Henry_B._Bigelow \
           --survey_name HB0905 \
           --sonar_model EK60 \
           --file_download_directory Henry_B._Bigelow_HB0905_EK60_NCEI
}

if spin_pretty "downloading D20090916-T132105.raw via aa-raw" _fetch_sample_raw; then
    RESULTS[sample-raw]="downloaded"
else
    warn "couldn't fetch the sample .raw file. Verify auth ('gcloud auth application-default login') then re-run the aa-raw command from the script."
    RESULTS[sample-raw]="failed"
fi


# ---------------------------------------------------------------------------
# 12. Closing block.
# ===========================================================================

if [[ $PLAIN_MODE -eq 0 ]]; then
    summary_rows=$(printf '%s\n' "${!RESULTS[@]}" | sort | while read -r k; do
        printf '| %-22s | %s |\n' "$k" "${RESULTS[$k]}"
    done)
    summary=$(printf '| %-22s | %s |\n| %s | %s |\n%s' \
        "Step" "Outcome" \
        "----------------------" "------------------------------" \
        "$summary_rows")

    gum style --border rounded --border-foreground 39 --padding "1 2" \
        --margin "2 0 1 0" --foreground 252 \
        "$summary"

    gum style --bold --foreground 39 --margin "1 0" "You're all set."
    gum style --foreground 252 --margin "0 0 0 2" \
        "Your AA-SI environment is installed and ready. Here's what to do first:" \
        "" \
        "  1.  cd ~                                        # drop into your home dir" \
        "  2.  aa-help --reindex                           # build the local knowledge DB (one-time)" \
        "  3.  aa-help \"what does aa-mvbs do?\"             # try it" \
        "" \
        "(GCP auth was completed earlier — re-run 'gcloud auth application-default login' if you ever need to refresh it.)" \
        "" \
        "Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*'" \
        "commands for actual data processing. 'aa-help --help' lists everything." \
        "" \
        "In Jupyter / VS Code notebooks, render any pipeline's output inline with:" \
        "" \
        "    aa_show(\"aa-sv input.raw | aa-graph\")" \
        "" \
        "(Both the PATH fix and the 'aa_show' helper are pre-installed — no setup cells needed.)"
    gum style --foreground 245 --margin "1 0" \
        "Knowledge directory:  $AA_DOCS_HOME" \
        "Repo prompts cache:   $REPO_PROMPTS_DIR" \
        "aa-help config:       $AA_HELP_CONFIG" \
        "IPython startup:      $IPYTHON_STARTUP_DIR"
else
    printf '\n=== Setup summary ===\n\n'
    for k in $(printf '%s\n' "${!RESULTS[@]}" | sort); do
        printf '  %-22s %s\n' "$k" "${RESULTS[$k]}"
    done
    cat <<EOF

You're all set. Here's what to do first:

  1.  cd ~                                        # drop into your home dir
  2.  aa-help --reindex                           # build the local knowledge DB
  3.  aa-help "what does aa-mvbs do?"             # try it

(GCP auth was completed earlier — re-run 'gcloud auth application-default login'
if you ever need to refresh it.)

Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*' commands
for actual data processing. 'aa-help --help' lists everything.

In Jupyter / VS Code notebooks, render any pipeline's output inline with:

    aa_show("aa-sv input.raw | aa-graph")

(Both the PATH fix and the 'aa_show' helper are pre-installed — no setup
cells needed.)

Knowledge directory:  $AA_DOCS_HOME
Repo prompts cache:   $REPO_PROMPTS_DIR
aa-help config:       $AA_HELP_CONFIG
IPython startup:      $IPYTHON_STARTUP_DIR
EOF
fi


# ---------------------------------------------------------------------------
# 13. Self-delete.
#
# Setup is one-shot — re-running it is a footgun (it would re-prompt for
# auth and re-download the sample .raw file). With `set -e` in effect,
# we only get here when every preceding step succeeded, so it's safe to
# remove ourselves now. If the script was piped from stdin (e.g.
# `curl ... | bash`) BASH_SOURCE[0] won't be a real file and the -f
# guard makes this a no-op.
# ---------------------------------------------------------------------------

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [[ -f "$SCRIPT_PATH" ]]; then
    if rm -f -- "$SCRIPT_PATH" 2>/dev/null; then
        info "removed $SCRIPT_PATH (one-shot setup is complete)."
    else
        warn "couldn't remove $SCRIPT_PATH — you can delete it manually."
    fi
fi