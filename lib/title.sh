#!/bin/bash
# Three-tier meeting title extraction

# Get meeting title from best available source
# Args: $1 = title_hint (from detection), $2 = transcript_path (optional)
# Returns: cleaned title on stdout
extract_title() {
    local title_hint="${1:-}"
    local transcript_path="${2:-}"

    # Tier 1: Window/tab title from detection
    if [[ -n "$title_hint" ]] && is_meaningful_title "$title_hint"; then
        clean_title "$title_hint"
        return
    fi

    # Tier 2: Calendar event
    local cal_title
    cal_title=$(get_calendar_title)
    if [[ -n "$cal_title" ]]; then
        clean_title "$cal_title"
        return
    fi

    # Tier 3: Claude-generated from transcript
    if [[ -n "$transcript_path" ]] && [[ -f "$transcript_path" ]]; then
        local claude_title
        claude_title=$(generate_title_from_transcript "$transcript_path")
        if [[ -n "$claude_title" ]]; then
            clean_title "$claude_title"
            return
        fi
    fi

    # Fallback
    echo "Meeting"
}

# Check if a title is meaningful (not just a generic app name)
is_meaningful_title() {
    local title="$1"
    local lower
    lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')

    # Reject generic titles
    case "$lower" in
        "zoom meeting"|"zoom"|"facetime"|"facetime call"|"phone call"|"google voice call"|""|" ")
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Clean up raw title for display
clean_title() {
    local title="$1"
    # Strip common suffixes
    title=$(echo "$title" | sed 's/ - Google Meet$//;s/ - Zoom$//;s/ | .*$//')
    # Remove leading/trailing whitespace
    title=$(echo "$title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$title"
}

# Query macOS Calendar for current meeting
get_calendar_title() {
    osascript -e '
        tell application "Calendar"
            set now to current date
            set bestMatch to ""
            repeat with aCal in calendars
                set evts to (every event of aCal whose start date ≤ now and end date ≥ now)
                repeat with e in evts
                    try
                        set desc to description of e
                        if desc contains "meet.google.com" or desc contains "zoom.us" or desc contains "facetime" or desc contains "teams" then
                            return summary of e
                        end if
                        if bestMatch is "" then
                            set bestMatch to summary of e
                        end if
                    on error
                        if bestMatch is "" then
                            set bestMatch to summary of e
                        end if
                    end try
                end repeat
            end repeat
            return bestMatch
        end tell
    ' 2>/dev/null || echo ""
}

# Generate title from transcript using Claude
generate_title_from_transcript() {
    local transcript_path="$1"
    local first_500
    first_500=$(head -c 2000 "$transcript_path")

    if [[ -z "$first_500" ]]; then
        echo ""
        return
    fi

    local result
    result=$(timeout "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" -p \
        "Given the beginning of this meeting transcript, generate a concise meeting title (3-7 words, no quotes, no punctuation). Output ONLY the title, nothing else.

Transcript:
$first_500" \
        --model "$CLAUDE_TITLE_MODEL" \
        --output-format text \
        2>/dev/null || echo "")

    # Trim whitespace and validate
    result=$(echo "$result" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ ${#result} -gt 2 ]] && [[ ${#result} -lt 80 ]]; then
        echo "$result"
    else
        echo ""
    fi
}
