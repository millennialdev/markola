#!/bin/bash
# Meeting detection across 5 platforms
# Returns: "platform|title_hint" or "none|"

detect_meeting() {
    local result

    # Priority order: Zoom > Meet > FaceTime > Phone > Voice
    result=$(detect_zoom)
    [[ -n "$result" ]] && { echo "$result"; return; }

    result=$(detect_google_meet)
    [[ -n "$result" ]] && { echo "$result"; return; }

    result=$(detect_facetime)
    [[ -n "$result" ]] && { echo "$result"; return; }

    result=$(detect_phone)
    [[ -n "$result" ]] && { echo "$result"; return; }

    result=$(detect_google_voice)
    [[ -n "$result" ]] && { echo "$result"; return; }

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
