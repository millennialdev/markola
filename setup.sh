#!/bin/bash
set -euo pipefail

echo "=== Markola Setup ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_MODELS_DIR="$HOME/.local/share/whisper-cpp/models"

# Step 1: Install Homebrew dependencies
echo "--- Step 1: Installing dependencies ---"

install_if_missing() {
    local formula="$1" check_cmd="${2:-$1}"
    if command -v "$check_cmd" &>/dev/null; then
        echo "  ✓ $formula already installed"
    else
        echo "  Installing $formula..."
        brew install "$formula"
    fi
}

install_cask_if_missing() {
    local cask="$1" check_name="$2"
    if system_profiler SPAudioDataType 2>/dev/null | grep -q "$check_name" || brew list --cask "$cask" &>/dev/null; then
        echo "  ✓ $cask already installed"
    else
        echo "  Installing $cask..."
        brew install --cask "$cask"
    fi
}

install_if_missing "whisper-cpp" "whisper-cpp"
install_if_missing "switchaudio-osx" "SwitchAudioSource"
install_if_missing "ffmpeg" "ffmpeg"
install_cask_if_missing "blackhole-2ch" "BlackHole 2ch"

echo ""

# Step 2: Download whisper model
echo "--- Step 2: Whisper model ---"
mkdir -p "$WHISPER_MODELS_DIR"

if [[ -f "$WHISPER_MODELS_DIR/ggml-medium.bin" ]]; then
    echo "  ✓ Medium model already downloaded"
else
    echo "  Downloading ggml-medium.bin (~1.5GB)..."
    curl -L --progress-bar \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
        -o "$WHISPER_MODELS_DIR/ggml-medium.bin"
    echo "  ✓ Model downloaded"
fi

echo ""

# Step 3: Create local data directories
echo "--- Step 3: Data directories ---"
mkdir -p "$HOME/.local/share/markola"/{recordings,logs}
mkdir -p "$HOME/Documents/Obsidian/Intercom/Meetings"
echo "  ✓ Directories created"

echo ""

# Step 4: Multi-output audio device setup
echo "--- Step 4: Audio device setup ---"

if SwitchAudioSource -a 2>/dev/null | grep -q "Markola Output"; then
    echo "  ✓ 'Markola Output' multi-output device already exists"
else
    echo ""
    echo "  ⚠ Manual step required: Create a Multi-Output Device"
    echo ""
    echo "  1. Open Audio MIDI Setup (Cmd+Space → type 'Audio MIDI Setup')"
    echo "  2. Click the '+' button at bottom-left → 'Create Multi-Output Device'"
    echo "  3. Check BOTH:"
    echo "     - Your current output (speakers, AirPods, etc.)"
    echo "     - 'BlackHole 2ch'"
    echo "  4. Right-click the new device → 'Use This Device For Sound Output' (optional)"
    echo "  5. Double-click to rename it to: Markola Output"
    echo ""
    echo "  Opening Audio MIDI Setup..."
    open "/Applications/Utilities/Audio MIDI Setup.app" 2>/dev/null || true
    echo ""
    read -rp "  Press Enter when done (or 's' to skip)... " response
    if [[ "$response" != "s" ]]; then
        if SwitchAudioSource -a 2>/dev/null | grep -q "Markola Output"; then
            echo "  ✓ 'Markola Output' device found"
        else
            echo "  ⚠ 'Markola Output' not found — recording will capture mic only"
            echo "    You can set this up later and re-run: markola setup"
        fi
    fi
fi

echo ""

# Step 5: Symlink CLI
echo "--- Step 5: CLI setup ---"
MARKOLA_BIN="$SCRIPT_DIR/markola.sh"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

if [[ -L "$LOCAL_BIN/markola" ]] || [[ -f "$LOCAL_BIN/markola" ]]; then
    rm -f "$LOCAL_BIN/markola"
fi
ln -s "$MARKOLA_BIN" "$LOCAL_BIN/markola"
chmod +x "$MARKOLA_BIN"
echo "  ✓ Symlinked: markola → $MARKOLA_BIN"

# Make all scripts executable
find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} \;
echo "  ✓ All scripts made executable"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick start:"
echo "  markola start        # Start the detection daemon"
echo "  markola status       # Check daemon status"
echo "  markola process FILE # Process an audio file manually"
echo ""
echo "Make sure '$LOCAL_BIN' is in your PATH."
