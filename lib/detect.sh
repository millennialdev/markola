#!/bin/bash
# Meeting detection across 5 platforms
# Returns: "platform|title_hint" or "none|"

detect_meeting() {
    local result

    # Priority order: specific platform detectors first (high confidence,
    # clean platform tag for bucketing), then hybrid fallback (any
    # non-blocklisted app holding a mic session).
    for fn in detect_zoom detect_google_meet detect_facetime \
              detect_teams detect_whatsapp detect_messenger \
              detect_instagram detect_snapchat \
              detect_phone detect_google_voice \
              detect_generic_call; do
        result=$($fn)
        [[ -n "$result" ]] && { echo "$result"; return; }
    done

    echo "none|"
}

# Zoom: check for active meeting window process
detect_zoom() {
    if pgrep -x "CptHost" &>/dev/null || pgrep -f "zoom.us.*meeting" &>/dev/null; then
        local title
        title=$(osascript -e '
            tell application "System Events"
                if exists process "zoom.us" then
                    tell process "zoom.us"
                        if (count of windows) > 0 then
                            return name of first window
                        end if
                    end tell
                end if
            end tell
            return ""
        ' 2>/dev/null || echo "")
        # Clean up generic titles
        if [[ "$title" == "Zoom Meeting" ]] || [[ -z "$title" ]]; then
            title="Zoom Meeting"
        fi
        echo "zoom|$title"
        return
    fi
    echo ""
}

# Google Meet: scan Chrome tabs for active meeting URLs
detect_google_meet() {
    # Only check if Chrome is running
    pgrep -x "Google Chrome" &>/dev/null || { echo ""; return; }

    local title
    title=$(osascript -e '
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURL to URL of t
                    if tabURL starts with "https://meet.google.com/" then
                        -- Exclude landing page (no meeting code)
                        if tabURL is not "https://meet.google.com/" and tabURL does not end with "meet.google.com/" then
                            set tabTitle to title of t
                            -- Strip " - Google Meet" suffix
                            if tabTitle ends with " - Google Meet" then
                                set tabTitle to text 1 thru -15 of tabTitle
                            end if
                            return tabTitle
                        end if
                    end if
                end repeat
            end repeat
            return ""
        end tell
    ' 2>/dev/null || echo "")

    if [[ -n "$title" ]]; then
        echo "meet|$title"
    else
        echo ""
    fi
}

# FaceTime: check for active A/V conference daemon
detect_facetime() {
    # avconferenced runs during FaceTime calls
    if pgrep -x "avconferenced" &>/dev/null; then
        # Distinguish FaceTime from phone — FaceTime.app should be running
        if pgrep -x "FaceTime" &>/dev/null; then
            local title
            title=$(osascript -e '
                tell application "System Events"
                    if exists process "FaceTime" then
                        tell process "FaceTime"
                            if (count of windows) > 0 then
                                return name of first window
                            end if
                        end tell
                    end if
                end tell
                return ""
            ' 2>/dev/null || echo "")
            echo "facetime|${title:-FaceTime Call}"
            return
        fi
    fi
    echo ""
}

# Phone via Mac: iPhone Continuity calls
detect_phone() {
    # callservicesd handles phone calls routed through Mac
    if pgrep -x "callservicesd" &>/dev/null && pgrep -x "avconferenced" &>/dev/null; then
        # Make sure it's not already claimed by FaceTime
        if ! pgrep -x "FaceTime" &>/dev/null; then
            echo "phone|Phone Call"
            return
        fi
    fi
    echo ""
}

# Google Voice: browser-based calling
detect_google_voice() {
    pgrep -x "Google Chrome" &>/dev/null || { echo ""; return; }
    # Only trigger if avconferenced is also active (WebRTC call in progress)
    pgrep -x "avconferenced" &>/dev/null || { echo ""; return; }

    local found
    found=$(osascript -e '
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURL to URL of t
                    if tabURL starts with "https://voice.google.com/" then
                        return "yes"
                    end if
                end repeat
            end repeat
            return ""
        end tell
    ' 2>/dev/null || echo "")

    if [[ "$found" == "yes" ]]; then
        echo "voice|Google Voice Call"
    else
        echo ""
    fi
}

# ── Helper: check if any open Chrome tab URL matches a regex ─────────
chrome_url_matches() {
    local pattern="$1"
    pgrep -x "Google Chrome" &>/dev/null || return 1
    osascript -e "
        tell application \"Google Chrome\"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t as string) contains \"$pattern\" then
                        return \"yes\"
                    end if
                end repeat
            end repeat
            return \"\"
        end tell
    " 2>/dev/null | grep -q "yes"
}

# ── Microsoft Teams ──────────────────────────────────────────────────
detect_teams() {
    if pgrep -x "Microsoft Teams" &>/dev/null \
       || pgrep -x "Microsoft Teams (work or school)" &>/dev/null \
       || pgrep -f "MSTeams" &>/dev/null; then
        local title
        title=$(osascript -e '
            tell application "System Events"
                repeat with procName in {"Microsoft Teams", "Microsoft Teams (work or school)", "MSTeams"}
                    try
                        tell process procName
                            if (count of windows) > 0 then
                                return name of first window
                            end if
                        end tell
                    end try
                end repeat
            end tell
            return ""
        ' 2>/dev/null || echo "")
        echo "teams|${title:-Teams Meeting}"
        return
    fi
    if chrome_url_matches "teams.microsoft.com" || chrome_url_matches "teams.live.com"; then
        echo "teams|Teams Meeting (web)"
        return
    fi
    echo ""
}

# ── WhatsApp (desktop or web) ────────────────────────────────────────
detect_whatsapp() {
    # Desktop app: process is "WhatsApp"; only fire if avconferenced active too
    # (otherwise app may just be open in background)
    if pgrep -x "WhatsApp" &>/dev/null && pgrep -x "avconferenced" &>/dev/null; then
        echo "whatsapp|WhatsApp Call"
        return
    fi
    # Web (any chrome tab on web.whatsapp.com + avconferenced)
    if chrome_url_matches "web.whatsapp.com" && pgrep -x "avconferenced" &>/dev/null; then
        echo "whatsapp|WhatsApp Web Call"
        return
    fi
    echo ""
}

# ── Facebook Messenger (desktop or web) ──────────────────────────────
detect_messenger() {
    if pgrep -x "Messenger" &>/dev/null && pgrep -x "avconferenced" &>/dev/null; then
        echo "messenger|Messenger Call"
        return
    fi
    if (chrome_url_matches "messenger.com" || chrome_url_matches "facebook.com/messages") \
       && pgrep -x "avconferenced" &>/dev/null; then
        echo "messenger|Messenger Web Call"
        return
    fi
    echo ""
}

# ── Instagram (web DM call) ──────────────────────────────────────────
detect_instagram() {
    # Instagram desktop app rare — assume web. Require avconferenced for confidence.
    if chrome_url_matches "instagram.com" && pgrep -x "avconferenced" &>/dev/null; then
        echo "instagram|Instagram Call"
        return
    fi
    echo ""
}

# ── Snapchat (desktop app) ───────────────────────────────────────────
detect_snapchat() {
    if pgrep -x "Snapchat" &>/dev/null && pgrep -x "avconferenced" &>/dev/null; then
        echo "snapchat|Snapchat Call"
        return
    fi
    if chrome_url_matches "web.snapchat.com" && pgrep -x "avconferenced" &>/dev/null; then
        echo "snapchat|Snapchat Web Call"
        return
    fi
    echo ""
}

# ── Generic VoIP fallback (catch-all, with smart blocklist) ──────────
# Fires only when avconferenced/audio session is active AND no specific
# platform detector matched AND the holding process isn't on the blocklist.
# Use this for: Discord voice, Skype, Telegram calls, Slack huddles,
# random VoIP apps, and anything we haven't explicitly added a detector for.
detect_generic_call() {
    # Require an audio conference daemon running — blocks most false positives
    # (just having Spotify open won't trigger this since avconferenced isn't running)
    pgrep -x "avconferenced" &>/dev/null || { echo ""; return; }

    # Apps we explicitly do NOT want to trigger recordings for, even if they
    # hold a mic session. Streaming/entertainment, dictation, audio editing,
    # markola itself, and platforms already detected by name.
    local BLOCKLIST=(
        # Streaming / entertainment / music
        "Spotify" "Music" "iTunes" "Podcasts" "TIDAL" "Pandora"
        "Netflix" "Hulu" "Disney+" "HBO" "Max" "Prime Video"
        "Plex" "Jellyfin" "Emby" "VLC" "mpv" "IINA" "QuickTime Player"
        "YouTube"
        # Dictation / speech-to-text (not meetings)
        "VoiceInk" "speechrecognitiond" "DictationIM" "Whisper" "whisper-cli" "whisper-cpp"
        # Audio production tools (intentional capture, not a meeting)
        "Audio Hijack" "Loopback" "GarageBand" "Logic Pro" "Pro Tools"
        "Background Music" "BlackHole"
        # markola itself + ffmpeg recording
        "ffmpeg" "markola"
        # Platforms already detected by specific functions (don't double-fire)
        "zoom.us" "CptHost" "FaceTime" "Microsoft Teams" "MSTeams"
        "WhatsApp" "Messenger" "Snapchat"
        # System / browser parents (chrome itself shouldn't trigger; tab match handles real cases)
        "Google Chrome" "Safari" "Firefox" "Brave Browser" "Arc"
    )

    # Walk processes that have audio device file handles open
    local mic_users
    mic_users=$(lsof -F c 2>/dev/null \
        | awk '/AppleHDA|CoreAudio|AudioUnit|VPIO/{getline; print}' \
        | grep "^c" | sort -u | sed 's/^c//' || true)

    for proc in $mic_users; do
        local blocked=0
        for blk in "${BLOCKLIST[@]}"; do
            if [[ "$proc" == *"$blk"* ]]; then
                blocked=1
                break
            fi
        done
        if [[ $blocked -eq 0 ]]; then
            # Sanitize for filesystem (lowercase, no spaces)
            local tag
            tag=$(echo "$proc" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
            echo "${tag:-generic}|Audio Call ($proc)"
            return
        fi
    done

    echo ""
}
