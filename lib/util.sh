#!/bin/bash
# Shared utilities: logging, notifications, cleanup

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Desktop notifications via macbook-config's notify.sh
notify() {
    local event_type="$1" title="$2" message="$3"
    local notify_script="$HOME/.ai-tools/notify.sh"
    if [[ -x "$notify_script" ]]; then
        "$notify_script" "$event_type" "$title" "$message" 2>/dev/null &
    fi
}

notify_recording_start() {
    local platform="$1" title="$2"
    notify "complete" "Markola" "Recording started: $platform — $title"
    log "Recording started: $platform — $title"
}

notify_recording_stop() {
    local title="$1"
    notify "complete" "Markola" "Recording stopped: $title"
    log "Recording stopped: $title"
}

notify_notes_ready() {
    local note_path="$1"
    local filename
    filename=$(basename "$note_path")
    notify "complete" "Markola" "Meeting notes saved: $filename"
    log "Meeting notes saved: $note_path"
}

notify_error() {
    local message="$1"
    notify "error" "Markola" "$message"
    err "$message"
}

# Sanitize a string for use as a filename
sanitize_title() {
    echo "$1" \
        | sed 's/[^a-zA-Z0-9 _-]//g' \
        | sed 's/  */ /g' \
        | sed 's/ /-/g' \
        | head -c 60
}

# Check available disk space (returns 0 if sufficient)
check_disk_space() {
    local min_mb="${1:-500}"
    local available_mb
    available_mb=$(df -m "$HOME" | awk 'NR==2 {print $4}')
    if [[ "$available_mb" -lt "$min_mb" ]]; then
        warn "Low disk space: ${available_mb}MB available (minimum: ${min_mb}MB)"
        return 1
    fi
    return 0
}

# Clean up old recordings past retention period
cleanup_old_recordings() {
    if [[ -d "$MARKOLA_RECORDING_DIR" ]]; then
        find "$MARKOLA_RECORDING_DIR" -name "*.wav" -mtime +"$RECORDING_RETENTION_DAYS" -delete 2>/dev/null
        find "$MARKOLA_RECORDING_DIR" -name "*.whisper-failed" -mtime +"$RECORDING_RETENTION_DAYS" -delete 2>/dev/null
        log "Cleaned recordings older than ${RECORDING_RETENTION_DAYS} days"
    fi
}

# Calculate duration between two epoch timestamps
format_duration() {
    local start="$1" end="$2"
    local total_seconds=$((end - start))
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    if [[ $minutes -gt 0 ]]; then
        echo "${minutes} min ${seconds} sec"
    else
        echo "${seconds} sec"
    fi
}
