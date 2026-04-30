#!/usr/bin/env bash
# AA-SI workstation init script.
# Idempotent: safe to re-run. Errors fail fast. All output is timestamped to
# stderr so it's easy to grep startup logs later.

set -euo pipefail

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

log "🔊🐟 Initializing AA-SI workstation..."
log "🏚️  Preparing workstation setup at $HOME..."
mkdir -p "$HOME"
log "🛠️  Base station ($HOME) is operational."


# ---------------------------------------------------------------------------
# 1. Remove the bad Helm repo from apt sources, if present.
# ---------------------------------------------------------------------------

BAD_REPO="https://baltocdn.com/helm/stable/debian"
log "🔎 Checking for bad Helm repo: $BAD_REPO"

# Use sudo for the grep too -- some apt source files are root-readable only.
FOUND_FILES=$(sudo grep -Rl "$BAD_REPO" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)
if [[ -n "$FOUND_FILES" ]]; then
    while IFS= read -r f; do
        log "⚠️  Found bad Helm repo in: $f -- removing"
        sudo rm -f "$f"
    done <<< "$FOUND_FILES"
else
    log "✅ No bad Helm repo found."
fi


# ---------------------------------------------------------------------------
# 2. System packages.
# ---------------------------------------------------------------------------

log "📦 Updating apt and upgrading system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq


# ---------------------------------------------------------------------------
# 3. Python 3.12 (build from source if not already present).
# ---------------------------------------------------------------------------

has_ensurepip() {
    command -v python3.12 >/dev/null 2>&1 \
        && python3.12 -m ensurepip --version >/dev/null 2>&1
}

if has_ensurepip; then
    log "✅ Usable Python 3.12 found at: $(command -v python3.12)"
elif [[ -x "$HOME/python312/bin/python3.12" ]]; then
    # Previous run installed it; just make sure PATH includes it.
    log "✅ Python 3.12 already built at \$HOME/python312, ensuring PATH..."
    export PATH="$HOME/python312/bin:$PATH"
    if ! grep -q 'HOME/python312/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/python312/bin:$PATH"' >> "$HOME/.bashrc"
    fi
else
    log "⬇️  Python 3.12 not found. Building 3.12.3 into \$HOME/python312..."

    sudo apt-get install -y -qq build-essential libssl-dev zlib1g-dev \
        libncurses5-dev libncursesw5-dev libreadline-dev libsqlite3-dev \
        libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev \
        tk-dev uuid-dev libffi-dev wget

    BUILD_DIR=$(mktemp -d -t py312-build-XXXXXX)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    pushd "$BUILD_DIR" >/dev/null

    wget -q https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz
    tar -xzf Python-3.12.3.tgz
    cd Python-3.12.3
    ./configure --prefix="$HOME/python312" --enable-optimizations -q
    make -j"$(nproc)" -s
    make install -s

    popd >/dev/null
    rm -rf "$BUILD_DIR"
    trap - EXIT

    if ! grep -q 'HOME/python312/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/python312/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/python312/bin:$PATH"
    log "✅ Python 3.12.3 installed to \$HOME/python312"
fi


# ---------------------------------------------------------------------------
# 4. Virtual environment.
# ---------------------------------------------------------------------------

if [[ ! -d "$HOME/venv312" ]]; then
    python3.12 -m venv "$HOME/venv312"
    log "✅ Created virtual environment at ~/venv312"
else
    log "✅ Virtual environment already exists at ~/venv312"
fi

# shellcheck disable=SC1091
source "$HOME/venv312/bin/activate"
log "✅ Activated venv. Python version: $(python --version)"


# ---------------------------------------------------------------------------
# 5. /opt payload (currently a no-op; kept as a placeholder for image-baked
#    payloads. Uncomment the cp lines if your image stages files in /opt).
# ---------------------------------------------------------------------------

if [[ -d /opt && -n "$(ls -A /opt 2>/dev/null)" ]]; then
    log "📦 /opt payload detected (currently no copies enabled)."
    # shopt -s dotglob
    # cp -r /opt/aa-scripts "$HOME"/
    # cp -r /opt/google-cloud-login.sh "$HOME"/
    # shopt -u dotglob
else
    log "🛑 /opt empty -- no payload to transfer."
fi


# ---------------------------------------------------------------------------
# 6. Aggregate docs/prompts/ from each AA-SI repo into ~/aa-docs/repo-prompts.
#
# We pip-install from git URLs, but the cloned source is deleted after pip
# finishes. To capture each repo's docs/prompts/ directory, we shallow-clone
# the repo to a temp dir, copy docs/prompts/, then discard the clone.
# ---------------------------------------------------------------------------

AA_DOCS_HOME="$HOME/aa-docs"
REPO_PROMPTS_DIR="$AA_DOCS_HOME/repo-prompts"
mkdir -p "$AA_DOCS_HOME" "$REPO_PROMPTS_DIR"
log "📂 Personal knowledge dir: $AA_DOCS_HOME"

# Stash the clones in a temp dir we'll wipe at the end.
CLONE_STAGE=$(mktemp -d -t aa-clones-XXXXXX)
trap 'rm -rf "$CLONE_STAGE"' EXIT

aggregate_prompts_from_repo() {
    # $1 = repo URL, $2 = friendly name for the output subdir
    local repo_url="$1"
    local name="$2"
    local clone_dir="$CLONE_STAGE/$name"
    local dest="$REPO_PROMPTS_DIR/$name"

    log "🧭 Cloning $name to extract docs/prompts/ ..."
    if ! git clone --depth 1 --quiet "$repo_url" "$clone_dir" 2>/dev/null; then
        log "  (skip: could not clone $repo_url)"
        return 0
    fi

    if [[ -d "$clone_dir/docs/prompts" ]]; then
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -r "$clone_dir/docs/prompts/." "$dest/"
        local count
        count=$(find "$dest" -type f | wc -l)
        log "  ✅ $name: copied $count prompt file(s) to $dest"
    else
        log "  (no docs/prompts/ in $name; skipping)"
    fi
}


# ---------------------------------------------------------------------------
# 7. Install AA-SI Python packages from GitHub.
#
# pip flags:
#   --no-cache-dir   ensures fresh source on every run
#   --force-reinstall guarantees the latest commit replaces a stale install
# We drop -vv (was producing thousands of lines of debug output).
# ---------------------------------------------------------------------------

pip install --quiet --upgrade pip
pip install --quiet pyworms matplotlib toml

log "🎣 Installing aalibrary (active acoustics core)..."
pip install --no-cache-dir --force-reinstall --quiet \
    git+https://github.com/nmfs-ost/AA-SI_aalibrary
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_aalibrary" "aalibrary"

log "🐡 Installing echoml (KMeans classification)..."
pip install --no-cache-dir --force-reinstall --quiet \
    git+https://github.com/nmfs-ost/AA-SI_KMeans
aggregate_prompts_from_repo "https://github.com/nmfs-ost/AA-SI_KMeans" "echoml"

log "🦈 Installing echosms + echoregions..."
pip install --quiet echosms echoregions


# ---------------------------------------------------------------------------
# 8. Jupyter kernel registration.
# ---------------------------------------------------------------------------

pip install --quiet ipykernel
python -m ipykernel install --user --name=venv312 --display-name "venv312"


# ---------------------------------------------------------------------------
# 9. Pre-seed aa-help config so first invocation just works.
#
# We only write the file if it doesn't already exist -- never clobber a config
# the user has tweaked. Set the project_id from $GOOGLE_CLOUD_PROJECT if
# available; otherwise leave it blank and let the user run `aa-help --setup`.
# ---------------------------------------------------------------------------

AA_HELP_CONFIG_DIR="$HOME/.config/aalibrary"
AA_HELP_CONFIG="$AA_HELP_CONFIG_DIR/aa_help.toml"
mkdir -p "$AA_HELP_CONFIG_DIR"

if [[ ! -f "$AA_HELP_CONFIG" ]]; then
    project_id="${GOOGLE_CLOUD_PROJECT:-}"
    log "📝 Writing default aa-help config to $AA_HELP_CONFIG"
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
        log "  ℹ️  GCP project ID not set in env; run 'aa-help --setup' to fill it in."
    else
        log "  ✅ Pre-populated project_id = $project_id"
    fi
else
    log "✅ aa-help config already exists; leaving it alone."
fi


# ---------------------------------------------------------------------------
# 10. Final summary.
# ---------------------------------------------------------------------------

log "📡 AA-SI environment is live."
log ""
log "Next steps:"
log "  1. cd ~                                   # back to home"
log "  2. gcloud auth application-default login  # if not already done"
log "  3. aa-help --reindex                      # build the knowledge DB"
log "  4. aa-help \"what does aa-mvbs do?\"        # verify it works"
log ""
log "Personal docs:    $AA_DOCS_HOME"
log "Repo prompts:     $REPO_PROMPTS_DIR"
log "aa-help config:   $AA_HELP_CONFIG"
