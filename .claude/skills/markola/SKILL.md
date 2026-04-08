---
name: markola
description: "Control the Markola meeting notes daemon, process audio/video files into meeting notes, browse recent notes, and troubleshoot. Use when: 'markola', 'meeting notes', 'start recording', 'stop recording', 'check meetings', 'process recording', 'meeting status', 'transcribe audio', 'transcribe meeting'"
---

# Markola — Local Meeting Notes

Markola auto-detects meetings (Google Meet, Zoom, FaceTime, Phone, Google Voice), records audio locally, transcribes via whisper-cpp, generates structured notes via Claude, and saves to Obsidian.

## Key Paths

- **CLI**: `markola` (symlinked to `~/Documents/GitHub/markola/markola.sh`)
- **Notes**: `~/Documents/Obsidian/Intercom/Meetings/`
- **Recordings**: `~/.local/share/markola/recordings/`
- **Logs**: `~/.local/share/markola/logs/`
- **Config**: `~/Documents/GitHub/markola/lib/config.sh`

## Commands

Run these via Bash tool:

| Command | Purpose |
|---------|---------|
| `markola start` | Start detection daemon |
| `markola stop` | Stop daemon (finishes current recording) |
| `markola status` | Show daemon state, active recording, recent notes |
| `markola pause` | Pause auto-detection |
| `markola resume` | Resume auto-detection |
| `markola record [title]` | Manual recording start |
| `markola stop-recording` | Stop manual recording and process |
| `markola process <file>` | Process any audio/video file into meeting notes |
| `markola setup` | First-time dependency install + audio device setup |
| `markola logs` | Show recent daemon logs |

## Common Workflows

### Check status
```bash
markola status
```

### Process an existing audio/video file
```bash
markola process /path/to/recording.mp4
```

### Browse recent meeting notes
```bash
ls -lt ~/Documents/Obsidian/Intercom/Meetings/ | head -10
```

### Read a specific meeting note
Use the Read tool on files in `~/Documents/Obsidian/Intercom/Meetings/`.

### Search meeting notes by keyword
```bash
grep -rl "keyword" ~/Documents/Obsidian/Intercom/Meetings/
```

### Check daemon logs for issues
```bash
tail -50 ~/.local/share/markola/logs/daemon.log
```

### Troubleshoot audio setup
```bash
# Check if BlackHole is installed
SwitchAudioSource -a | grep BlackHole

# Check if Markola Output device exists
SwitchAudioSource -a | grep "Markola Output"

# List all audio devices
SwitchAudioSource -a
```

## Error Recovery

- If transcription fails, the audio file is preserved with a `.whisper-failed` marker
- If Claude fails, raw transcript is saved as the note body
- Re-process any failed recording: `markola process ~/.local/share/markola/recordings/<file>.wav`

## Setup

If markola is not installed, guide the user through:
1. `cd ~/Documents/GitHub/markola && ./setup.sh`
2. Create "Markola Output" multi-output device in Audio MIDI Setup
3. `markola start` to begin detection
