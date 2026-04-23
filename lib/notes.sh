#!/bin/bash
# Meeting note generation via Claude and Obsidian save

# Generate meeting notes from a transcript
# Args: $1 = transcript_path, $2 = platform, $3 = start_epoch, $4 = end_epoch, $5 = title
generate_meeting_notes() {
    local transcript_path="$1"
    local platform="$2"
    local start_epoch="$3"
    local end_epoch="${4:-$(date +%s)}"
    local title="$5"

    local date_str time_str duration platform_tag
    date_str=$(date -r "$start_epoch" '+%Y-%m-%d')
    time_str=$(date -r "$start_epoch" '+%H:%M')
    duration=$(format_duration "$start_epoch" "$end_epoch")
    platform_tag=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

    local transcript
    transcript=$(cat "$transcript_path")

    if [[ -z "$transcript" ]]; then
        warn "Empty transcript — generating stub note"
        generate_stub_note "$platform" "$start_epoch" "$end_epoch" "$title" "$transcript_path"
        return
    fi

    # Read prompt template and substitute variables
    local prompt_file="$MARKOLA_HOME/prompts/generate-notes.prompt"
    local prompt
    prompt=$(cat "$prompt_file")
    prompt="${prompt//\{\{PLATFORM\}\}/$platform}"
    prompt="${prompt//\{\{DATE\}\}/$date_str}"
    prompt="${prompt//\{\{TIME\}\}/$time_str}"
    prompt="${prompt//\{\{DURATION\}\}/$duration}"
    prompt="${prompt//\{\{TITLE\}\}/$title}"
    prompt="${prompt//\{\{PLATFORM_TAG\}\}/$platform_tag}"
    prompt="${prompt//\{\{TRANSCRIPT\}\}/$transcript}"

    log "Generating meeting notes via Claude ($CLAUDE_NOTE_MODEL)..."
    local start_time note_content
    start_time=$(date +%s)

    note_content=$(timeout "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" -p "$prompt" \
        --model "$CLAUDE_NOTE_MODEL" \
        --output-format text \
        2>"$MARKOLA_LOG_DIR/claude-stderr.log" || echo "")

    local gen_time
    gen_time=$(date +%s)
    log "Note generation took $(format_duration "$start_time" "$gen_time")"

    if [[ -z "$note_content" ]]; then
        warn "Claude note generation failed — saving raw transcript"
        generate_raw_transcript_note "$platform" "$start_epoch" "$end_epoch" "$title" "$transcript_path"
        return
    fi

    # Save to Obsidian (bucketed by platform)
    save_to_obsidian "$note_content" "$start_epoch" "$title" "$platform_tag"
}

# Save note content to Obsidian vault, bucketed under platform-type subdir.
# Path layout: $OBSIDIAN_MEETINGS_DIR/<platform>/YYYY-MM-DD_HHMMSS_title.md
# e.g. ~/Documents/markola/zoom/2026-04-23_143012_daily-standup.md
save_to_obsidian() {
    local content="$1"
    local start_epoch="$2"
    local title="$3"
    local platform_tag="${4:-uncategorized}"

    local date_part time_part sanitized_title filename
    date_part=$(date -r "$start_epoch" '+%Y-%m-%d')
    time_part=$(date -r "$start_epoch" '+%H%M%S')
    sanitized_title=$(sanitize_title "$title")
    filename="${date_part}_${time_part}_${sanitized_title}.md"

    local note_dir="$OBSIDIAN_MEETINGS_DIR/$platform_tag"
    mkdir -p "$note_dir"
    local note_path="$note_dir/$filename"
    echo "$content" > "$note_path"
    notify_notes_ready "$note_path"
}

# Generate a stub note when transcription fails
generate_stub_note() {
    local platform="$1" start_epoch="$2" end_epoch="$3" title="$4" audio_path="$5"
    local date_str time_str duration platform_tag
    date_str=$(date -r "$start_epoch" '+%Y-%m-%d')
    time_str=$(date -r "$start_epoch" '+%H:%M')
    duration=$(format_duration "$start_epoch" "$end_epoch")
    platform_tag=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

    local content="---
type: meeting
date: $date_str
time: \"$time_str\"
duration: \"$duration\"
platform: $platform_tag
tags:
  - meeting
  - $platform_tag
  - needs-transcription
---

# $title

## Summary
Transcription failed. Audio file preserved for manual retry.

## Audio File
\`$audio_path\`

To retry: \`markola process $audio_path\`
"
    save_to_obsidian "$content" "$start_epoch" "$title" "$platform_tag"
}

# Generate a note with raw transcript when Claude fails
generate_raw_transcript_note() {
    local platform="$1" start_epoch="$2" end_epoch="$3" title="$4" transcript_path="$5"
    local date_str time_str duration platform_tag transcript
    date_str=$(date -r "$start_epoch" '+%Y-%m-%d')
    time_str=$(date -r "$start_epoch" '+%H:%M')
    duration=$(format_duration "$start_epoch" "$end_epoch")
    platform_tag=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    transcript=$(cat "$transcript_path")

    local content="---
type: meeting
date: $date_str
time: \"$time_str\"
duration: \"$duration\"
platform: $platform_tag
tags:
  - meeting
  - $platform_tag
  - needs-summarization
---

# $title

## Summary
Note generation failed. Raw transcript preserved below.

To regenerate: \`markola process ${transcript_path%.txt}.wav\`

## Transcript

$transcript
"
    save_to_obsidian "$content" "$start_epoch" "$title" "$platform_tag"
}

# Full processing pipeline for a recording
process_recording() {
    local recording_path="$1"

    local platform start_epoch title_hint
    platform=$(get_state_field platform)
    start_epoch=$(get_state_field start)
    title_hint=$(get_state_field title)
    local end_epoch
    end_epoch=$(date +%s)

    log "Processing recording: $(basename "$recording_path")"

    # Step 1: Transcribe
    local transcript_path
    transcript_path=$(transcribe_audio "$recording_path") || {
        generate_stub_note "${platform:-unknown}" "${start_epoch:-$(date +%s)}" "$end_epoch" "${title_hint:-Meeting}" "$recording_path"
        return
    }

    # Step 2: Extract title
    local title
    title=$(extract_title "$title_hint" "$transcript_path")

    # Step 3: Generate notes
    generate_meeting_notes "$transcript_path" "${platform:-unknown}" "${start_epoch:-$(date +%s)}" "$end_epoch" "$title"

    log "Processing complete: $title"
}

# Process an arbitrary audio/video file (manual invocation)
process_file() {
    local input_file="$1"
    local start_epoch
    start_epoch=$(date +%s)

    # Convert to WAV if needed
    local wav_path
    case "$input_file" in
        *.wav)
            wav_path="$input_file"
            ;;
        *)
            wav_path=$(convert_to_wav "$input_file") || {
                err "Failed to convert: $input_file"
                return 1
            }
            ;;
    esac

    # Transcribe
    local transcript_path
    transcript_path=$(transcribe_audio "$wav_path") || {
        err "Transcription failed for: $wav_path"
        return 1
    }

    # Extract title
    local title
    title=$(extract_title "" "$transcript_path")

    # Generate notes
    local end_epoch
    end_epoch=$(date +%s)
    generate_meeting_notes "$transcript_path" "manual" "$start_epoch" "$end_epoch" "$title"
}
