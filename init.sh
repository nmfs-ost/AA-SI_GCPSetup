#!/bin/bash
set -e  # Exit immediately if any command fails

echo "🔊🐟 Initializing..."

# --- Ensure the home directory exists ---
echo "🏚️ Preparing workstation setup at $HOME..."
mkdir -p "$HOME"
echo "🛠️ Base station ($HOME) is operational."
sudo apt update
sudo apt upgrade -y

# --- Copy files from /opt to $HOME if /opt is not empty ---
if [ -d /opt ] && [ "$(ls -A /opt)" ]; then
    echo "📦 /opt sonar payload detected. Transferring to base station..."

    shopt -s dotglob  # Include hidden files (like camouflaged cephalopods 🦑)
    # cp -r /opt/aa-scripts "$HOME"/
    # cp -r /opt/google-cloud-login.sh "$HOME"/
    shopt -u dotglob

    echo "🎯 Payload deployed to $HOME — assets ready."
else
    echo "🛑 /opt empty — no acoustic data to transfer."
fi

# --- Install Python 3.10 and venv unconditionally ---
echo "🔧 Installing Python 3.13 and venv tools..."
sudo apt update
sudo apt install -y python3.13-venv

# --- Set up Python virtual environment and install packages ---
echo "🔧 Setting up AA-SI environment..."
cd "$HOME"

ENV_NAME="aa_si"
echo "🧪 Creating virtual environment: $ENV_NAME"
python3.10 -m venv "$ENV_NAME"
source "$ENV_NAME/bin/activate"

pip install --upgrade pip

# Install acoustic processing packages
echo "🐬 Installing acoustics tools into $ENV_NAME..."

echo "🎣 Installing AA-SI_aalibrary (active signal interpretation)..."
pip install --no-cache-dir -vv --force-reinstall git+https://github.com/nmfs-ost/AA-SI_aalibrary

echo "🐡 Installing echoml (echo classification & ML)..."
pip install --no-cache-dir -vv --force-reinstall git+https://github.com/spacetimeengineer/echoml.git@d4c8bbd

echo "🦈 Installing echosms (system management for sonar ops)..."
pip install echosms

echo "✅ Python environment $ENV_NAME is fully configured for aquatic signal processing."

# --- Final instructions ---
echo "📡 AA-SI environment is live and ready for use."
echo "🔁 Navigate to home directory with: cd"
echo "🧭 Review transferred files and verify AA-SI readiness. Enter 'aa-help' for a command reference with examples."
