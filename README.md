# Markola

Local-first meeting notes tool for macOS. Auto-detects meetings, records audio, transcribes locally via [whisper-cpp](https://github.com/ggerganov/whisper.cpp), generates structured notes via Claude, and saves to Obsidian.

**Audio never leaves your machine.** Only the text transcript is sent to the Claude API for note generation.

## How It Works

```
Meeting detected → ffmpeg records (mic + system audio via BlackHole)
                → whisper-cpp transcribes locally
                → Claude generates structured notes
                → saves to Obsidian vault as markdown
```

## Supported Platforms

- Google Meet (Chrome)
- Zoom
- FaceTime
- Phone calls via Mac (iPhone Continuity)
- Google Voice (Chrome)

## Quick Start

```bash
# 1. Install dependencies
./setup.sh

# 2. Create the multi-output audio device (setup.sh guides you)

# 3. Start the daemon
markola start

# 4. Join a meeting — notes appear automatically in Obsidian
```

## Commands

| Command | Description |
|---------|-------------|
| `markola start` | Start the detection daemon |
| `markola stop` | Stop the daemon (finishes current recording) |
| `markola status` | Show daemon state, active recording, recent notes |
| `markola pause` | Pause auto-detection |
| `markola resume` | Resume auto-detection |
| `markola record [title]` | Start manual recording |
| `markola stop-recording` | Stop manual recording and process |
| `markola process <file>` | Process any audio/video file into notes |
| `markola setup` | Run first-time setup |
| `markola logs` | Show recent daemon logs |

## Architecture

### Detection
Daemon polls every 5 seconds for meeting signals:
- **Zoom**: Process detection (`CptHost`)
- **Google Meet**: Chrome tab URL scanning via AppleScript
- **FaceTime/Phone**: `avconferenced` process detection
- **Google Voice**: Chrome tab URL + `avconferenced`

Requires 2 consecutive detections (10s) before recording starts. 30-second grace period before stopping.

### Audio Capture
- **BlackHole 2ch** virtual audio device captures system audio (what others say)
- **Multi-Output Device** sends audio to both speakers AND BlackHole
- **ffmpeg** merges system audio + microphone into mono 16kHz WAV

### Processing Pipeline
1. **whisper-cpp** (medium model, ~1.5GB) transcribes locally on Apple Silicon
2. **Title extraction**: window title → calendar event → Claude-generated fallback
3. **Claude** generates structured notes with YAML frontmatter
4. Saves to `~/Documents/Obsidian/Intercom/Meetings/`

### Error Handling
- Whisper fails → audio preserved, stub note with retry command
- Claude fails → raw transcript saved as note body
- ffmpeg crashes → partial audio processed
- Low disk → recording stops, notification sent

## Dependencies

| Package | Install | Purpose |
|---------|---------|---------|
| whisper-cpp | `brew install whisper-cpp` | Local speech-to-text |
| blackhole-2ch | `brew install --cask blackhole-2ch` | Virtual audio device |
| switchaudio-osx | `brew install switchaudio-osx` | Audio device switching |
| ffmpeg | `brew install ffmpeg` | Audio recording/conversion |
| claude | Claude Code CLI | Note generation |

## Configuration

All defaults in `lib/config.sh` can be overridden via environment variables:

```bash
export OBSIDIAN_VAULT="$HOME/Documents/MyVault"
export WHISPER_THREADS=8
export CLAUDE_NOTE_MODEL=opus
export POLL_INTERVAL=3
```

## File Locations

| Path | Purpose |
|------|---------|
| `~/.local/share/markola/` | Local data (recordings, logs, state) |
| `~/Documents/Obsidian/Intercom/Meetings/` | Generated meeting notes |
| `~/.local/share/whisper-cpp/models/` | Whisper model files |

## LaunchAgent (Optional)

A LaunchAgent plist is included at `schedule/com.markola.daemon.plist` for auto-start on login. To install:

```bash
# Edit the plist — replace __MARKOLA_HOME__ and __HOME__ with actual paths
cp schedule/com.markola.daemon.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.markola.daemon.plist
```

## License

MIT
