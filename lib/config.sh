#!/bin/bash
# Markola configuration — all defaults can be overridden via environment variables

# Directories
MARKOLA_HOME="${MARKOLA_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MARKOLA_DATA_DIR="${MARKOLA_DATA_DIR:-$HOME/.local/share/markola}"
MARKOLA_LOG_DIR="$MARKOLA_DATA_DIR/logs"
MARKOLA_RECORDING_DIR="$MARKOLA_DATA_DIR/recordings"

# Obsidian
OBSIDIAN_VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian}"
OBSIDIAN_MEETINGS_DIR="$OBSIDIAN_VAULT/Intercom/Meetings"

# Audio devices
BLACKHOLE_DEVICE="${BLACKHOLE_DEVICE:-BlackHole 2ch}"
MULTI_OUTPUT_DEVICE="${MULTI_OUTPUT_DEVICE:-Markola Output}"
AUDIO_SAMPLE_RATE="${AUDIO_SAMPLE_RATE:-16000}"

# Detection tuning
POLL_INTERVAL="${POLL_INTERVAL:-5}"
DETECTION_THRESHOLD="${DETECTION_THRESHOLD:-2}"       # consecutive polls before recording
GRACE_PERIOD_POLLS="${GRACE_PERIOD_POLLS:-6}"          # polls after meeting disappears (30s)

# Whisper
WHISPER_BIN="${WHISPER_BIN:-$(which whisper-cli 2>/dev/null || echo "/opt/homebrew/bin/whisper-cli")}"
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper-cpp/models/ggml-medium.bin}"
WHISPER_THREADS="${WHISPER_THREADS:-6}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-en}"

# Claude
CLAUDE_BIN="${CLAUDE_BIN:-$(which claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
CLAUDE_NOTE_MODEL="${CLAUDE_NOTE_MODEL:-sonnet}"
CLAUDE_TITLE_MODEL="${CLAUDE_TITLE_MODEL:-haiku}"
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-120}"

# ffmpeg
FFMPEG_BIN="${FFMPEG_BIN:-$(which ffmpeg 2>/dev/null || echo "/opt/homebrew/bin/ffmpeg")}"

# SwitchAudioSource
SWITCH_AUDIO_BIN="${SWITCH_AUDIO_BIN:-$(which SwitchAudioSource 2>/dev/null || echo "/opt/homebrew/bin/SwitchAudioSource")}"

# Cleanup
RECORDING_RETENTION_DAYS="${RECORDING_RETENTION_DAYS:-7}"

# State files
PID_FILE="$MARKOLA_DATA_DIR/daemon.pid"
FFMPEG_PID_FILE="$MARKOLA_DATA_DIR/ffmpeg.pid"
STATE_FILE="$MARKOLA_DATA_DIR/state"
PAUSE_FILE="$MARKOLA_DATA_DIR/paused"
ORIGINAL_OUTPUT_FILE="$MARKOLA_DATA_DIR/original_output"

# Ensure directories exist
mkdir -p "$MARKOLA_DATA_DIR" "$MARKOLA_LOG_DIR" "$MARKOLA_RECORDING_DIR" "$OBSIDIAN_MEETINGS_DIR"
