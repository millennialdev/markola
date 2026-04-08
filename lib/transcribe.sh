#!/bin/bash
# Whisper-cpp transcription wrapper

# Transcribe a WAV file, output .txt alongside it
# Args: $1 = path to WAV file
# Returns: path to transcript file on stdout
transcribe_audio() {
    local audio_path="$1"

    if [[ ! -f "$audio_path" ]]; then
        err "Audio file not found: $audio_path"
        return 1
    fi

    if ! command -v "$WHISPER_BIN" &>/dev/null; then
        err "whisper-cpp not found at $WHISPER_BIN — run 'markola setup'"
        return 1
    fi

    if [[ ! -f "$WHISPER_MODEL" ]]; then
        err "Whisper model not found at $WHISPER_MODEL — run 'markola setup'"
        return 1
    fi

    local base_path="${audio_path%.wav}"
    local transcript_path="${base_path}.txt"

    log "Transcribing: $(basename "$audio_path")"
    local start_time
    start_time=$(date +%s)

    "$WHISPER_BIN" \
        -m "$WHISPER_MODEL" \
        -otxt \
        -of "$base_path" \
        -t "$WHISPER_THREADS" \
        -l "$WHISPER_LANGUAGE" \
        "$audio_path" \
        2>"$MARKOLA_LOG_DIR/whisper-stderr.log"

    local exit_code=$?
    local end_time
    end_time=$(date +%s)
    local duration
    duration=$(format_duration "$start_time" "$end_time")

    if [[ $exit_code -ne 0 ]] || [[ ! -s "$transcript_path" ]]; then
        warn "Whisper transcription failed (exit code: $exit_code)"
        touch "${audio_path}.whisper-failed"
        return 1
    fi

    log "Transcription complete in $duration: $(basename "$transcript_path")"
    echo "$transcript_path"
}

# Convert non-WAV audio/video to WAV format suitable for whisper
# Args: $1 = input file path
# Returns: path to converted WAV on stdout
convert_to_wav() {
    local input_path="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_path="$MARKOLA_RECORDING_DIR/${timestamp}_converted.wav"

    log "Converting to WAV: $(basename "$input_path")"

    "$FFMPEG_BIN" \
        -i "$input_path" \
        -ac 1 \
        -ar "$AUDIO_SAMPLE_RATE" \
        -c:a pcm_s16le \
        "$output_path" \
        -y -nostdin -loglevel warning \
        2>"$MARKOLA_LOG_DIR/ffmpeg-convert.log"

    if [[ $? -ne 0 ]] || [[ ! -f "$output_path" ]]; then
        err "Failed to convert: $input_path"
        return 1
    fi

    echo "$output_path"
}
