#!/usr/bin/env bash
# AA-SI workstation setup.
#
# Idempotent and safe to re-run, but designed for a first-time user: the
# voice walks you through what's being set up and why, sets expectations
# for how long things take, and ends with a clear "what to try first."
#
# This variant assumes the base image already has Python 3.13 installed
# and creates the venv at ~/venv313.
#
# PACKAGE MANAGER: this variant uses `uv` (https://docs.astral.sh/uv/)
# instead of pip. Three things change for anyone reading this script:
#
#   1) Every `pip install X` is now `uv pip install X`. Same CLI surface,
#      same semantics, roughly 10-50x faster because uv resolves in
#      parallel and hardlinks from a global cache instead of re-downloading
#      and re-unpacking every wheel.
#
#   2) Flag names differ slightly. pip's `--no-cache-dir` is uv's
#      `--no-cache`; pip's `--force-reinstall` is uv's `--reinstall`.
#      For git sources, `--refresh` is what re-pulls from GitHub (the old
#      `--no-cache-dir` was doing that job before).
#
#   3) The zarr fight (see section 7b in the pip version) is gone. uv
#      supports an OVERRIDES file, which lets us tell the resolver to
#      ignore aalibrary's stale `zarr==2.8.3` pin and echoregions'
#      `zarr<3` pin outright, rather than installing the wrong zarr and
#      force-upgrading it afterward and hoping install order works out.
#      That file is written in section 4a and passed to every install
#      through the `uvpip` wrapper.
#
# Everything else — the venv location, the tools installed, the Jupyter
# glue, the aa-help config — is unchanged.

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
    "Total time: about 1–2 minutes on a fresh GCP image, faster on re-run." \
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
# 2a. Install the uv package manager.
#
# uv is a single static binary — no Python dependency, nothing to keep in
# sync with the venv it manages. Two install routes, in order:
#
#   1) The official installer from astral.sh. Fastest, always current.
#   2) `pip install --user uv` from PyPI. Fallback for networks where
#      astral.sh isn't reachable but PyPI is (common behind an agency
#      proxy allowlist — this script already needs PyPI and GitHub, so
#      route 2 needs no new firewall exceptions).
#
# The installer drops the binary in ~/.local/bin (same dir gum went into,
# already on PATH by this point) and appends a PATH line to your shell rc
# so `uv` is there in future sessions too.
# ---------------------------------------------------------------------------

section "Installing the uv package manager"
note "uv replaces pip for this setup. It resolves dependencies in parallel and hardlinks wheels from a shared cache, which is why the installs below take seconds rather than minutes."

UV_INSTALL_DIR="$GUM_DIR"
export UV_INSTALL_DIR

_install_uv_upstream() {
    curl -LsSf --connect-timeout 10 https://astral.sh/uv/install.sh | sh
}

_install_uv_pypi() {
    python3 -m pip install --user --upgrade uv
}

if command -v uv >/dev/null 2>&1; then
    success "uv is already installed ($(uv --version))."
    RESULTS[package-manager]="uv (pre-existing)"
else
    if spin_pretty "downloading uv from astral.sh" _install_uv_upstream; then
        RESULTS[package-manager]="uv (upstream installer)"
    elif spin_pretty "astral.sh unreachable — installing uv from PyPI" _install_uv_pypi; then
        RESULTS[package-manager]="uv (PyPI fallback)"
    else
        problem "couldn't install uv from astral.sh or PyPI."
        problem "Check that one of those hosts is reachable from this machine, then re-run."
        exit 1
    fi

    export PATH="$UV_INSTALL_DIR:$PATH"

    if ! command -v uv >/dev/null 2>&1; then
        # PyPI route puts it in ~/.local/bin too via --user, but honour
        # whatever `python3 -m site --user-base` actually says.
        _user_bin="$(python3 -m site --user-base 2>/dev/null || true)/bin"
        [[ -d "$_user_bin" ]] && export PATH="$_user_bin:$PATH"
    fi

    if ! command -v uv >/dev/null 2>&1; then
        problem "uv installed but isn't on PATH. Look for the binary under ~/.local/bin and add it manually."
        exit 1
    fi
    success "uv is ready ($(uv --version))."
fi


# ---------------------------------------------------------------------------
# 3. Python 3.13.
#
# This image ships with Python 3.13 already installed, so normally we just
# verify it's present. Unlike the pip version of this script, a missing
# 3.13 is no longer fatal: uv can fetch its own managed CPython build in
# about 20 seconds, which is strictly better than telling the user to go
# find another image.
#
# The old `ensurepip` check is gone. `uv venv` doesn't call ensurepip —
# it writes the venv layout itself and seeds pip from a bundled wheel —
# so a system Python missing python3.13-venv is no longer a blocker.
# ---------------------------------------------------------------------------

section "Making sure Python 3.13 is available"
note "AA-SI tools target Python 3.13. This image ships with it pre-installed; if it's missing, uv fetches a managed build instead of failing."

if command -v python3.13 >/dev/null 2>&1; then
    success "Python 3.13 is ready at $(command -v python3.13) ($(python3.13 --version))."
    RESULTS[python]="system (pre-installed)"
else
    warn "python3.13 isn't on PATH — asking uv to fetch a managed build."
    if spin_pretty "downloading a managed CPython 3.13" uv python install 3.13; then
        success "uv-managed Python 3.13 installed."
        RESULTS[python]="uv-managed"
    else
        problem "couldn't obtain Python 3.13 from the system or from uv."
        problem "Check network access to astral.sh / GitHub releases, then re-run."
        exit 1
    fi
fi


# ---------------------------------------------------------------------------
# 4. Virtual environment.
#
# `--seed` installs pip/setuptools/wheel into the venv. uv itself never
# needs them, but users will absolutely type `pip install something` in
# this venv later, and a venv where that fails with "command not found"
# is a support ticket waiting to happen.
# ---------------------------------------------------------------------------

section "Creating your AA-SI virtual environment"
note "Everything AA-SI installs lives in ~/venv313, isolated from system Python. The venv auto-activates from your shell once setup is done."

if [[ ! -d "$HOME/venv313" ]]; then
    spin_pretty "creating the venv" uv venv --python 3.13 --seed "$HOME/venv313"
    RESULTS[venv]="created"
else
    success "~/venv313 already exists — reusing it."
    RESULTS[venv]="reused"
fi

# shellcheck disable=SC1091
source "$HOME/venv313/bin/activate"

# uv picks its install target from $VIRTUAL_ENV. `activate` sets it, but we
# export it explicitly so the value survives into the subshells spin_pretty
# uses, and so a stale VIRTUAL_ENV from the parent shell can't win.
export VIRTUAL_ENV="$HOME/venv313"

success "venv active. You're now using $(python --version)."


# ---------------------------------------------------------------------------
# 4a. Dependency overrides.
#
# This is the piece that replaces the old "install the wrong zarr, then
# force-upgrade it and hope install order settles in echopype's favour"
# dance (section 7b in the pip version).
#
# The conflict itself hasn't gone away:
#
#   * aalibrary 1.2.0's metadata pins `zarr==2.8.3`, a stale pin from
#     years ago that nothing in the code actually requires.
#   * echoregions 0.2.3's PyPI wheel pins `zarr<3`.
#   * echopype 0.11+ imports `zarr.codecs.BloscCodec`, a zarr-3 API, so
#     it needs `zarr>=3`.
#
# pip has no way to say "ignore that pin", so the old script installed
# everything and then shoved zarr back up afterwards, leaving pip to
# print a dependency-conflict warning we had to explain away as cosmetic.
#
# uv supports an overrides file, which does exactly what's needed: any
# requirement matching a line here is REPLACED, wherever it appears in
# the tree, before resolution happens. No conflict, no warning, no
# ordering dependency. Every install below goes through `uvpip`, which
# passes this file.
#
# When aalibrary's pin is finally fixed upstream, delete the zarr line
# here and the override file becomes empty — that's the signal that this
# workaround is no longer load-bearing.
# ---------------------------------------------------------------------------

AA_CONFIG_HOME="$HOME/.config/aalibrary"
UV_OVERRIDES="$AA_CONFIG_HOME/uv-overrides.txt"
mkdir -p "$AA_CONFIG_HOME"

cat > "$UV_OVERRIDES" <<'OVR'
# Dependency overrides applied to every uv install in ~/venv313.
# Written by AA-SI init.sh — re-running setup overwrites this file.
#
# aalibrary pins zarr==2.8.3 and echoregions 0.2.3 pins zarr<3, but
# echopype 0.11+ needs zarr>=3 (it imports zarr.codecs.BloscCodec).
# Overriding here means uv never considers the stale pins at all.
zarr>=3,<4
OVR

# Every install in this script goes through this wrapper so the overrides
# can't be forgotten on one line and silently break the environment.
uvpip() {
    uv pip install --override "$UV_OVERRIDES" "$@"
}

success "dependency overrides written to $UV_OVERRIDES"
RESULTS[uv-overrides]="zarr>=3,<4"


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
#
# Flag translation from the pip version:
#
#   pip install --no-cache-dir --force-reinstall git+https://...
#   uv pip install --reinstall --refresh    git+https://...
#
# `--no-cache-dir` was doing two jobs in the old script: forcing a fresh
# pull from GitHub, and avoiding stale wheels. Under uv those split into
# `--refresh` (re-fetch the git checkout and rebuild) and `--reinstall`
# (replace what's already in the venv). We deliberately do NOT pass
# `--no-cache` globally — uv's cache is what makes re-runs near-instant,
# and it's content-addressed, so it can't go stale the way pip's could.
# ---------------------------------------------------------------------------

section "Installing AA-SI tools"
note "These are the actual data-processing libraries. Each install pulls fresh source from GitHub, then we cache the docs into your knowledge directory."

# NOTE: no `pip install --upgrade pip` here. uv does its own resolution and
# never shells out to pip; the seeded pip in the venv is only there as an
# escape hatch for the user.
spin_pretty "installing common scientific deps (matplotlib, toml, pyworms)" \
    uvpip pyworms matplotlib toml

section "Installing aalibrary"
note "The core data-fetch and processing library. Includes the 'aa-*' command-line tools you'll use every day."
spin_pretty "downloading and installing aalibrary" \
    uvpip --reinstall --refresh \
        git+https://github.com/nmfs-ost/AA-SI_aalibrary
RESULTS[pkg-aalibrary]="installed"
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_aalibrary" "aalibrary"

section "Installing AA-SI_KMeans"
note "K-means and ML utilities for echo classification."
spin_pretty "downloading and installing AA-SI_KMeans" \
    uvpip --reinstall --refresh \
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
#
# Under uv, problem (2) is already handled — the overrides file from
# section 4a replaces that pin during resolution, so the PyPI wheel no
# longer drags zarr backwards. Problem (1) is unaffected by the package
# manager, so we still prefer the git install: building from a git
# checkout lets setuptools-scm read tags and emit the version stub.
#
# WATCH THIS ONE on the first uv run. uv fetches git dependencies into
# its own cache, and how much history it pulls determines whether
# setuptools-scm can see a tag. If it can't, you'll get a package whose
# __version__ is a dev string — harmless — but if the build fails
# outright, the PyPI fallback below catches it exactly as before.
# ---------------------------------------------------------------------------

section "Installing echosms and echoregions"
note "Sister libraries for scattering models (echosms) and Echoview region handling (echoregions). echoregions is installed from its GitHub main branch, not PyPI — see the comment above this section in init.sh for why."

spin_pretty "installing echosms (PyPI)" uvpip echosms
RESULTS[pkg-echosms]="installed"

# These are wrapped in functions so spin_pretty can run them as a single
# command and capture their full output for its tail-of-log display.
_install_echoregions_from_git() {
    uvpip --reinstall --refresh \
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
            uvpip --reinstall echoregions; then
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
# 7b. Confirm zarr landed on 3.x.
#
# In the pip version this section did real work: it force-upgraded zarr
# after the fact to undo aalibrary's stale `zarr==2.8.3` pin, and printed
# a "this dependency-conflict warning is cosmetic" disclaimer.
#
# With the overrides file from section 4a, zarr should already be correct
# — no install ever saw the 2.8.3 pin. This is now a cheap assertion so a
# regression shows up here, next to the explanation, rather than three
# weeks later as an ImportError on zarr.codecs.BloscCodec.
# ---------------------------------------------------------------------------

section "Confirming the zarr version"
note "aalibrary's metadata pins an old zarr; echopype needs zarr>=3. The overrides file handled that during resolution — this just double-checks the result."

_check_zarr() {
    python - <<'PY'
import sys
import zarr
major = int(zarr.__version__.split(".")[0])
print(f"zarr {zarr.__version__}")
if major < 3:
    print("ERROR: zarr must be >=3 for echopype 0.11+ (zarr.codecs.BloscCodec)")
    sys.exit(1)
PY
}

if spin_pretty "checking zarr>=3" _check_zarr; then
    RESULTS[zarr-pin]="zarr>=3,<4 (via overrides)"
else
    warn "zarr came out below 3 despite the override — repairing directly."
    if spin_pretty "forcing zarr>=3" uvpip --upgrade "zarr>=3,<4"; then
        RESULTS[zarr-pin]="zarr>=3,<4 (repaired)"
    else
        problem "couldn't get zarr>=3 installed. echopype will fail to import."
        RESULTS[zarr-pin]="FAILED"
    fi
fi


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

spin_pretty "installing ipykernel" uvpip ipykernel
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
# 8b. Fetch the sample region.evr file.
#
# An Echoview region-definition file from AA-SI_GCPSetup that pairs
# with the sample .raw we fetch later — gives users a working region
# to feed into aa-evr without having to draw their own. Same approach
# as the Examples notebook above: pull from raw.githubusercontent.com
# (the blob/ URL would return HTML, not the file), drop in $HOME,
# best-effort on failure.
# ---------------------------------------------------------------------------

section "Fetching the sample region.evr file"
note "Drops region.evr (an Echoview region definition from AA-SI_GCPSetup) into your home directory so you have a working input ready for 'aa-evr'."

REGION_EVR_URL="https://raw.githubusercontent.com/nmfs-ost/AA-SI_GCPSetup/main/region.evr"
REGION_EVR_PATH="$HOME/region.evr"

_fetch_region_evr() {
    curl -fsSL --connect-timeout 10 "$REGION_EVR_URL" -o "$REGION_EVR_PATH"
}

if spin_pretty "downloading region.evr to $REGION_EVR_PATH" _fetch_region_evr; then
    success "region.evr is at $REGION_EVR_PATH"
    RESULTS[region-evr]="downloaded"
else
    warn "couldn't download region.evr. You can fetch it manually from $REGION_EVR_URL"
    RESULTS[region-evr]="skipped (network)"
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

AA_HELP_CONFIG_DIR="$AA_CONFIG_HOME"
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
# 11. AA-SI Workbench (browser-based workspace).
#
# The Workbench drives the same aa-* tools installed above — it is an
# orchestrator, not a separate stack — so it must live in THIS venv, where
# aalibrary is importable.
#
# Three things make this step unlike the pip installs above:
#
#   1) It is installed EDITABLE (-e) from a clone we keep at
#      ~/AA-SI_Workbench. The launcher finds the compiled UI by walking up
#      from the installed package to a directory holding both frontend/ and
#      backend/. A regular install lands in site-packages, finds no such
#      siblings, and cannot serve the UI. The clone has to stay put.
#
#   2) It is installed with --no-deps. Under pip this was essential: handing
#      the resolver aalibrary's stale zarr==2.8.3 pin again made it backtrack
#      through echopype releases for tens of minutes, occasionally landing on
#      a version with no Python 3.13 wheel and compiling from source. uv's
#      overrides file (section 4a) defuses that conflict, and uv reports an
#      unsolvable resolution in seconds rather than backtracking into it —
#      so --no-deps is now belt-and-braces rather than load-bearing. Keeping
#      it means this step installs exactly the packages we name and nothing
#      can quietly move a version out from under sections 7-7b. If you ever
#      want the Workbench's own metadata to be authoritative, dropping
#      --no-deps here is now a safe experiment.
#
#   3) The browser UI is TypeScript that npm/Vite compiles once into three
#      static files. Node is needed ONLY for that build, never at runtime —
#      at runtime it is a single Python process serving those files next to
#      /api on one port. We build here so the first launch is instant and a
#      build failure surfaces during setup rather than in front of a user.
#      If Node is unavailable we skip it; `aa-workbench` builds on first
#      launch instead.
# ---------------------------------------------------------------------------

section "Installing the AA-SI Workbench"
note "A browser-based workspace for the aa-* tools: browse NCEI surveys, assemble processing pipelines, and view results. It installs into this venv and pre-compiles its UI (about 2 minutes) so the first launch is instant."

WORKBENCH_DIR="$HOME/AA-SI_Workbench"
WORKBENCH_REPO="https://github.com/nmfs-ost/AA-SI_Workbench"

_clone_or_update_workbench() {
    # Never let git block on a credential prompt. spin_pretty redirects output
    # to a log file, so an interactive "Username for https://github.com:"
    # prompt is invisible AND unanswerable — setup would hang forever on a
    # private or missing repo. These two make git fail fast instead, so the
    # error below actually reaches the user.
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/bin/true

    if [[ -d "$WORKBENCH_DIR/.git" ]]; then
        # --ff-only refuses to invent a merge, which is right — but it also
        # fails hard when the remote history was rewritten (force-push, repo
        # recreated). A checkout we cloned ourselves has nothing worth
        # preserving, so re-clone rather than leave the user stuck.
        if git -C "$WORKBENCH_DIR" pull --ff-only; then
            return 0
        fi
        echo "pull failed (history rewritten?) — re-cloning"
        rm -rf "$WORKBENCH_DIR"
    fi
    git clone "$WORKBENCH_REPO" "$WORKBENCH_DIR" || return 1

    # The repo must have backend/ at its root. If someone published the parent
    # folder by mistake, everything downstream fails in confusing ways.
    if [[ ! -f "$WORKBENCH_DIR/backend/pyproject.toml" ]]; then
        echo "clone has no backend/pyproject.toml at its root:"
        ls -1 "$WORKBENCH_DIR" | head
        return 1
    fi
}

_install_workbench() {
    # `&&`, not two statements: a shell function returns the exit code of its
    # LAST command, so without this a failed editable install is masked by the
    # dependency install succeeding — and the step reports a green tick.
    uvpip --no-deps -e "$WORKBENCH_DIR/backend" \
        && uvpip \
            "fastapi>=0.110" "uvicorn[standard]>=0.29" "pydantic>=2.6" \
            "boto3>=1.34" "google-cloud-storage>=2.14"
}

_verify_workbench() {
    python -c "import aa_si_workbench, aa_si_workbench.api.main; print('workbench', aa_si_workbench.__version__)"
}

if spin_pretty "fetching the Workbench source" _clone_or_update_workbench \
        && spin_pretty "installing the Workbench into venv313" _install_workbench \
        && spin_pretty "verifying the Workbench imports" _verify_workbench; then
    RESULTS[workbench]="installed"

    # Compile the browser UI. Build-time only — nothing below runs again
    # when the user launches the Workbench.
    if ! command -v npm >/dev/null 2>&1; then
        note "Node.js isn't present. It's needed once to compile the UI (never to run it), so we'll try to install it."
        spin_pretty "installing Node.js (one-time, build only)" \
            sudo apt-get install -y -qq nodejs npm || true
    fi

    if command -v npm >/dev/null 2>&1; then
        if spin_pretty "compiling the Workbench UI (1-2 min, one-time)" aa-workbench build; then
            RESULTS[workbench-ui]="pre-built"
        else
            warn "the UI didn't compile. 'aa-workbench' will retry the build on first launch."
            RESULTS[workbench-ui]="deferred to first launch"
        fi
    else
        warn "no Node.js available — skipping the UI build. 'aa-workbench' will build it on first launch (needs Node 18+)."
        RESULTS[workbench-ui]="deferred to first launch"
    fi
else
    problem "the Workbench didn't install. If the clone failed, check that $WORKBENCH_REPO is reachable from this machine — a private repo needs 'gh auth login' here first. Your aa-* command-line tools are unaffected."
    RESULTS[workbench]="FAILED"
fi


# ---------------------------------------------------------------------------
# 12. Fetch a sample raw acoustic data file.
#
# Run this almost last so any auth-related failure surfaces only after
# every other step has finished — nothing earlier needs GCP creds, so
# there's no reason to gate the whole script on an interactive login.
#
# aa-raw reads from a Google Cloud bucket, which needs Application
# Default Credentials. On the GCP images this script is meant for,
# ADC are already provisioned from the image itself, so this step is
# non-interactive and just works. We deliberately do NOT call
# `gcloud auth application-default login` preemptively — on those
# images it would trigger a redundant interactive flow for no benefit,
# and on images where it IS needed, the user only needs to run it once
# (the credentials persist), so we'd rather they discover that via a
# clear failure message here than be prompted up front every time.
#
# Best-effort: a failure here won't stop setup. The if/else handles
# the non-zero exit cleanly under `set -e`.
# ---------------------------------------------------------------------------

section "Fetching a sample EK60 .raw file"
note "Pulls one file from the Bigelow HB0905 survey via 'aa-raw' so you have real data to try the tools against. Uses your existing GCP credentials — no separate login step. Best-effort: a failure here won't stop setup."

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
    warn "couldn't fetch the sample .raw file. If the error above mentions credentials, ADC, or auth, run 'gcloud auth application-default login' once and then re-run the aa-raw command from this section of the script."
    RESULTS[sample-raw]="failed"
fi


# ---------------------------------------------------------------------------
# 13. Closing block.
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
        "  4.  aa-workbench --open                         # open the browser workspace" \
        "" \
        "(GCP credentials are read from your environment. If aa-raw or aa-help complain about auth, run 'gcloud auth application-default login' once.)" \
        "" \
        "Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*'" \
        "commands for actual data processing. 'aa-help --help' lists everything." \
        "" \
        "To add packages to this venv, prefer 'uv pip install <pkg>' over plain" \
        "'pip install' — it's the same syntax, much faster, and it respects the" \
        "zarr override that keeps echopype working:" \
        "" \
        "    uv pip install --override $UV_OVERRIDES <pkg>" \
        "" \
        "In Jupyter / VS Code notebooks, render any pipeline's output inline with:" \
        "" \
        "    aa_show(\"aa-sv input.raw | aa-graph\")" \
        "" \
        "(Both the PATH fix and the 'aa_show' helper are pre-installed — no setup cells needed.)"
    gum style --foreground 245 --margin "1 0" \
        "Workbench source:     $WORKBENCH_DIR" \
        "Knowledge directory:  $AA_DOCS_HOME" \
        "Repo prompts cache:   $REPO_PROMPTS_DIR" \
        "aa-help config:       $AA_HELP_CONFIG" \
        "uv overrides:         $UV_OVERRIDES" \
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
  4.  aa-workbench --open                         # open the browser workspace

(GCP credentials are read from your environment. If aa-raw or aa-help
complain about auth, run 'gcloud auth application-default login' once.)

Day-to-day, you'll mostly use 'aa-help' for guidance and the 'aa-*' commands
for actual data processing. 'aa-help --help' lists everything.

To add packages to this venv, prefer 'uv pip install <pkg>' over plain
'pip install' — same syntax, much faster, and it respects the zarr override
that keeps echopype working:

    uv pip install --override $UV_OVERRIDES <pkg>

In Jupyter / VS Code notebooks, render any pipeline's output inline with:

    aa_show("aa-sv input.raw | aa-graph")

(Both the PATH fix and the 'aa_show' helper are pre-installed — no setup
cells needed.)

Workbench source:     $WORKBENCH_DIR
Knowledge directory:  $AA_DOCS_HOME
Repo prompts cache:   $REPO_PROMPTS_DIR
aa-help config:       $AA_HELP_CONFIG
uv overrides:         $UV_OVERRIDES
IPython startup:      $IPYTHON_STARTUP_DIR
EOF
fi


# ---------------------------------------------------------------------------
# 14. Self-delete.
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
