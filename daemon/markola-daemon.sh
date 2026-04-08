#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/record.sh"
source "$SCRIPT_DIR/lib/transcribe.sh"
source "$SCRIPT_DIR/lib/notes.sh"
source "$SCRIPT_DIR/lib/title.sh"

log "Markola daemon starting (PID $$)"

# Cleanup on exit
cleanup_on_exit() {
    log "Daemon shutting down..."
    if [[ "$(get_state)" == "RECORDING" ]]; then
        log "Stopping active recording before exit"
        stop_recording
        local recording_path
        recording_path=$(get_state_field path)
        if [[ -f "$recording_path" ]]; then
            log "Processing final recording synchronously..."
            process_recording "$recording_path"
        fi
    fi
    rm -f "$PID_FILE"
    set_state_idle
    log "Daemon stopped"
}

trap cleanup_on_exit EXIT INT TERM

# Initialize state
set_state_idle
detected_count=0
grace_count=0
disk_check_counter=0

log "Detection active — polling every ${POLL_INTERVAL}s"

while true; do
    # Check pause state — skip detection but still manage active recordings
    if is_paused; then
        if [[ "$(get_state)" != "RECORDING" ]]; then
            sleep "$POLL_INTERVAL"
            continue
        fi
        # If recording, fall through to manage it
    fi

    current_state=$(get_state)

    # If recording, enforce audio device and check ffmpeg health
    if [[ "$current_state" == "RECORDING" ]]; then
        enforce_audio_output

        if ! check_ffmpeg_alive; then
            warn "ffmpeg died — processing partial recording"
            local recording_path
            recording_path=$(get_state_field path)
            restore_audio_output
            if [[ -f "$recording_path" ]]; then
                process_recording "$recording_path" &
            fi
            set_state_idle
            detected_count=0
            grace_count=0
            sleep "$POLL_INTERVAL"
            continue
        fi

        # Periodic disk space check during recording
        ((disk_check_counter++))
        if [[ $((disk_check_counter % 12)) -eq 0 ]]; then
            if ! check_disk_space; then
                warn "Low disk space — stopping recording"
                stop_recording
                local recording_path
                recording_path=$(get_state_field path)
                if [[ -f "$recording_path" ]]; then
                    process_recording "$recording_path" &
                fi
                set_state_idle
                notify_error "Recording stopped due to low disk space"
            fi
        fi
    fi

    # Run detection
    meeting_info=$(detect_meeting)
    platform=$(echo "$meeting_info" | cut -d'|' -f1)
    title_hint=$(echo "$meeting_info" | cut -d'|' -f2)

    case "$current_state" in
        IDLE)
            if [[ "$platform" != "none" ]]; then
                ((detected_count++))
                if [[ $detected_count -ge $DETECTION_THRESHOLD ]]; then
                    log "Meeting confirmed: $platform — $title_hint"
                    start_recording "$platform" "$title_hint"
                    detected_count=0
                    grace_count=0
                    disk_check_counter=0
                fi
            else
                detected_count=0
            fi
            ;;

        RECORDING)
            if [[ "$platform" == "none" ]]; then
                ((grace_count++))
                if [[ $grace_count -ge $GRACE_PERIOD_POLLS ]]; then
                    log "Meeting ended (grace period expired)"
                    stop_recording
                    local recording_path
                    recording_path=$(get_state_field path)
                    # Process in background so daemon can detect next meeting immediately
                    if [[ -f "$recording_path" ]]; then
                        process_recording "$recording_path" &
                    fi
                    set_state_idle
                    grace_count=0
                fi
            else
                grace_count=0
            fi
            ;;
    esac

    # Clean up old recordings periodically (once per hour = 720 polls at 5s)
    if [[ $((disk_check_counter % 720)) -eq 0 ]] && [[ $disk_check_counter -gt 0 ]]; then
        cleanup_old_recordings
    fi

    sleep "$POLL_INTERVAL"
done
