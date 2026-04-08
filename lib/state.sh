#!/bin/bash
# State machine management
# State file format: STATE|platform|start_epoch|recording_path|title_hint

get_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cut -d'|' -f1 < "$STATE_FILE"
    else
        echo "IDLE"
    fi
}

get_state_field() {
    local field="$1"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return
    fi
    case "$field" in
        state)     cut -d'|' -f1 < "$STATE_FILE" ;;
        platform)  cut -d'|' -f2 < "$STATE_FILE" ;;
        start)     cut -d'|' -f3 < "$STATE_FILE" ;;
        path)      cut -d'|' -f4 < "$STATE_FILE" ;;
        title)     cut -d'|' -f5 < "$STATE_FILE" ;;
    esac
}

set_state() {
    local state="$1"
    local platform="${2:-}"
    local start_epoch="${3:-}"
    local recording_path="${4:-}"
    local title_hint="${5:-}"
    echo "${state}|${platform}|${start_epoch}|${recording_path}|${title_hint}" > "$STATE_FILE"
}

set_state_idle() {
    set_state "IDLE"
}

is_paused() {
    [[ -f "$PAUSE_FILE" ]]
}

is_daemon_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill -0 "$pid" 2>/dev/null
        return $?
    fi
    return 1
}

print_status() {
    echo "=== Markola Status ==="
    echo ""

    if is_daemon_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "Daemon:    RUNNING (PID $pid)"
    else
        echo "Daemon:    STOPPED"
    fi

    if is_paused; then
        echo "Detection: PAUSED"
    else
        echo "Detection: ACTIVE"
    fi

    local current_state
    current_state=$(get_state)
    echo "State:     $current_state"

    if [[ "$current_state" == "RECORDING" ]]; then
        local platform start_epoch title_hint
        platform=$(get_state_field platform)
        start_epoch=$(get_state_field start)
        title_hint=$(get_state_field title)
        local now
        now=$(date +%s)
        local duration
        duration=$(format_duration "$start_epoch" "$now")

        echo ""
        echo "--- Active Recording ---"
        echo "Platform:  $platform"
        echo "Title:     ${title_hint:-Unknown}"
        echo "Duration:  $duration"
        echo "Started:   $(date -r "$start_epoch" '+%Y-%m-%d %H:%M:%S')"
    fi

    if [[ "$current_state" == "PROCESSING" ]]; then
        echo ""
        echo "--- Processing ---"
        local recording_path
        recording_path=$(get_state_field path)
        echo "File:      $recording_path"
    fi

    echo ""
    echo "Data dir:  $MARKOLA_DATA_DIR"
    echo "Notes dir: $OBSIDIAN_MEETINGS_DIR"

    # Recent notes
    local recent_notes
    recent_notes=$(ls -t "$OBSIDIAN_MEETINGS_DIR"/*.md 2>/dev/null | head -3)
    if [[ -n "$recent_notes" ]]; then
        echo ""
        echo "--- Recent Notes ---"
        while IFS= read -r note; do
            echo "  $(basename "$note")"
        done <<< "$recent_notes"
    fi
}
