#!/bin/bash
# Audio recording management via ffmpeg

# Verify audio devices are properly configured
verify_audio_setup() {
    local warnings=0

    if ! command -v "$FFMPEG_BIN" &>/dev/null; then
        err "ffmpeg not found at $FFMPEG_BIN — run 'markola setup'"
        return 1
    fi

    if ! command -v "$SWITCH_AUDIO_BIN" &>/dev/null; then
        warn "SwitchAudioSource not found — audio device switching disabled"
        ((warnings++))
    fi

    if ! "$SWITCH_AUDIO_BIN" -a 2>/dev/null | grep -q "$BLACKHOLE_DEVICE"; then
        warn "BlackHole not found — will record microphone only (no system audio)"
        ((warnings++))
    fi

    if ! "$SWITCH_AUDIO_BIN" -a 2>/dev/null | grep -q "$MULTI_OUTPUT_DEVICE"; then
        warn "'$MULTI_OUTPUT_DEVICE' device not found — will record microphone only"
        warn "Run 'markola setup' to configure the multi-output device"
        ((warnings++))
    fi

    if [[ $warnings -gt 0 ]]; then
        log "Audio setup has $warnings warning(s) — recording will use microphone only"
    fi
    return 0
}

# Check if BlackHole + multi-output device are available for full capture
has_system_audio() {
    "$SWITCH_AUDIO_BIN" -a 2>/dev/null | grep -q "$BLACKHOLE_DEVICE" && \
    "$SWITCH_AUDIO_BIN" -a 2>/dev/null | grep -q "$MULTI_OUTPUT_DEVICE"
}

# Save current audio output and switch to Markola Output
switch_to_markola_output() {
    if has_system_audio; then
        local current_output
        current_output=$("$SWITCH_AUDIO_BIN" -c -t output 2>/dev/null || echo "")
        if [[ -n "$current_output" ]]; then
            echo "$current_output" > "$ORIGINAL_OUTPUT_FILE"
            "$SWITCH_AUDIO_BIN" -s "$MULTI_OUTPUT_DEVICE" -t output 2>/dev/null
            log "Switched audio output to '$MULTI_OUTPUT_DEVICE' (was: $current_output)"
        fi
    fi
}

# Restore original audio output
restore_audio_output() {
    if [[ -f "$ORIGINAL_OUTPUT_FILE" ]]; then
        local original
        original=$(cat "$ORIGINAL_OUTPUT_FILE")
        if [[ -n "$original" ]]; then
            "$SWITCH_AUDIO_BIN" -s "$original" -t output 2>/dev/null || true
            log "Restored audio output to '$original'"
        fi
        rm -f "$ORIGINAL_OUTPUT_FILE"
    fi
}

# Enforce Markola Output during recording (handles AirPods reconnect, etc.)
enforce_audio_output() {
    if has_system_audio; then
        local current_output
        current_output=$("$SWITCH_AUDIO_BIN" -c -t output 2>/dev/null || echo "")
        if [[ "$current_output" != "$MULTI_OUTPUT_DEVICE" ]]; then
            "$SWITCH_AUDIO_BIN" -s "$MULTI_OUTPUT_DEVICE" -t output 2>/dev/null || true
            log "Audio output drifted to '$current_output', switched back to '$MULTI_OUTPUT_DEVICE'"
        fi
    fi
}

# Start recording
start_recording() {
    local platform="$1"
    local title_hint="$2"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local recording_path="$MARKOLA_RECORDING_DIR/${timestamp}_${platform}.wav"
    local start_epoch
    start_epoch=$(date +%s)

    # Check disk space
    if ! check_disk_space; then
        notify_error "Cannot start recording — low disk space"
        return 1
    fi

    # Switch audio output for system audio capture
    switch_to_markola_output

    # Build ffmpeg command based on available devices
    if has_system_audio; then
        # Full capture: system audio + microphone
        "$FFMPEG_BIN" \
            -f avfoundation -i ":${BLACKHOLE_DEVICE}" \
            -f avfoundation -i ":default" \
            -filter_complex "[0:a][1:a]amerge=inputs=2,pan=mono|c0=0.5*c0+0.5*c1[a]" \
            -map "[a]" \
            -ac 1 \
            -ar "$AUDIO_SAMPLE_RATE" \
            -c:a pcm_s16le \
            "$recording_path" \
            -y -nostdin -loglevel warning \
            >> "$MARKOLA_LOG_DIR/ffmpeg.log" 2>&1 &
    else
        # Mic-only fallback
        "$FFMPEG_BIN" \
            -f avfoundation -i ":default" \
            -ac 1 \
            -ar "$AUDIO_SAMPLE_RATE" \
            -c:a pcm_s16le \
            "$recording_path" \
            -y -nostdin -loglevel warning \
            >> "$MARKOLA_LOG_DIR/ffmpeg.log" 2>&1 &
    fi

    echo $! > "$FFMPEG_PID_FILE"
    set_state "RECORDING" "$platform" "$start_epoch" "$recording_path" "$title_hint"
    notify_recording_start "$platform" "$title_hint"
}

# Stop recording
stop_recording() {
    if [[ -f "$FFMPEG_PID_FILE" ]]; then
        local ffmpeg_pid
        ffmpeg_pid=$(cat "$FFMPEG_PID_FILE")
        # Send SIGINT for graceful stop (ffmpeg flushes buffers)
        kill -INT "$ffmpeg_pid" 2>/dev/null || true
        # Wait up to 5 seconds
        local wait=5
        while kill -0 "$ffmpeg_pid" 2>/dev/null && [[ $wait -gt 0 ]]; do
            sleep 1
            ((wait--))
        done
        # Force kill if still running
        kill -9 "$ffmpeg_pid" 2>/dev/null || true
        rm -f "$FFMPEG_PID_FILE"
    fi

    # Restore audio output
    restore_audio_output

    local title_hint
    title_hint=$(get_state_field title)
    notify_recording_stop "${title_hint:-Recording}"
}

# Check if ffmpeg recording process is alive
check_ffmpeg_alive() {
    if [[ -f "$FFMPEG_PID_FILE" ]]; then
        local ffmpeg_pid
        ffmpeg_pid=$(cat "$FFMPEG_PID_FILE")
        if ! kill -0 "$ffmpeg_pid" 2>/dev/null; then
            warn "ffmpeg process died unexpectedly"
            rm -f "$FFMPEG_PID_FILE"
            return 1
        fi
    fi
    return 0
}
