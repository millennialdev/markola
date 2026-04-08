#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/record.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/transcribe.sh"
source "$SCRIPT_DIR/lib/notes.sh"
source "$SCRIPT_DIR/lib/title.sh"

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    start)
        if is_daemon_running; then
            echo "Markola daemon already running (PID $(cat "$PID_FILE"))"
            exit 1
        fi
        verify_audio_setup || exit 1
        nohup "$SCRIPT_DIR/daemon/markola-daemon.sh" >> "$MARKOLA_LOG_DIR/daemon.log" 2>&1 &
        echo $! > "$PID_FILE"
        log "Daemon started (PID $!)"
        echo "Markola daemon started. Use 'markola status' to check."
        ;;

    start-foreground)
        # For LaunchAgent use — runs in foreground
        verify_audio_setup || exit 1
        echo $$ > "$PID_FILE"
        exec "$SCRIPT_DIR/daemon/markola-daemon.sh"
        ;;

    stop)
        if ! is_daemon_running; then
            echo "Markola daemon not running"
            exit 0
        fi
        local_pid=$(cat "$PID_FILE")
        echo "Stopping daemon (PID $local_pid)..."
        kill "$local_pid" 2>/dev/null || true
        # Wait for graceful shutdown
        timeout=30
        while kill -0 "$local_pid" 2>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done
        if kill -0 "$local_pid" 2>/dev/null; then
            kill -9 "$local_pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
        set_state_idle
        log "Daemon stopped"
        echo "Markola daemon stopped."
        ;;

    status)
        print_status
        ;;

    pause)
        touch "$PAUSE_FILE"
        echo "Detection paused. Active recording will finish normally."
        log "Detection paused by user"
        ;;

    resume)
        rm -f "$PAUSE_FILE"
        echo "Detection resumed."
        log "Detection resumed by user"
        ;;

    record)
        # Manual recording start
        if [[ "$(get_state)" == "RECORDING" ]]; then
            echo "Already recording. Use 'markola stop-recording' first."
            exit 1
        fi
        verify_audio_setup || exit 1
        start_recording "manual" "${1:-Manual Recording}"
        echo "Recording started. Use 'markola stop-recording' to stop."
        ;;

    stop-recording)
        if [[ "$(get_state)" != "RECORDING" ]]; then
            echo "Not currently recording."
            exit 1
        fi
        stop_recording
        local recording_path
        recording_path=$(get_state_field path)
        echo "Recording stopped: $recording_path"
        echo "Processing..."
        process_recording "$recording_path"
        ;;

    process)
        # Process an existing audio/video file
        local_file="${1:-}"
        if [[ -z "$local_file" ]]; then
            echo "Usage: markola process <audio-or-video-file>"
            exit 1
        fi
        if [[ ! -f "$local_file" ]]; then
            echo "File not found: $local_file"
            exit 1
        fi
        echo "Processing: $local_file"
        process_file "$local_file"
        ;;

    setup)
        exec "$SCRIPT_DIR/setup.sh"
        ;;

    logs)
        local_logfile="$MARKOLA_LOG_DIR/daemon.log"
        if [[ -f "$local_logfile" ]]; then
            tail -50 "$local_logfile"
        else
            echo "No daemon log found."
        fi
        ;;

    help|--help|-h)
        echo "markola — local meeting notes tool"
        echo ""
        echo "Usage: markola <command> [args]"
        echo ""
        echo "Commands:"
        echo "  start            Start the detection daemon"
        echo "  stop             Stop the daemon"
        echo "  status           Show daemon and recording status"
        echo "  pause            Pause auto-detection"
        echo "  resume           Resume auto-detection"
        echo "  record [title]   Start manual recording"
        echo "  stop-recording   Stop manual recording and process"
        echo "  process <file>   Process an audio/video file"
        echo "  setup            Run first-time setup"
        echo "  logs             Show recent daemon logs"
        echo "  help             Show this help"
        ;;

    *)
        echo "Unknown command: $COMMAND"
        echo "Run 'markola help' for usage."
        exit 1
        ;;
esac
