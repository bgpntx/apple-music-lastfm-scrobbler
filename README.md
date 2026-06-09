# Apple Music Last.fm Scrobbler

Native macOS command-line scrobbler for Apple Music and Last.fm.

This is intentionally small: it polls Music.app, sends `track.updateNowPlaying`, and scrobbles a track after Last.fm's standard threshold is reached. Other players are out of scope.

## Features

- Apple Silicon native Swift CLI.
- Apple Music only, read through macOS Automation/JXA.
- Last.fm desktop auth flow.
- `track.updateNowPlaying` and `track.scrobble` support.
- Last.fm scrobble rule: longer than 30 seconds, then half the observed playback or 4 minutes, whichever comes first.
- Retry queue for failed scrobbles.
- Per-user `launchd` agent install/uninstall commands.

## Requirements

- macOS 14 or newer.
- Xcode command-line tools with Swift 6 or newer.
- Apple Music.app.
- A Last.fm API key and shared secret.

## Build

```sh
swift build -c release
```

The release binary is written to:

```text
.build/release/scrobbler
```

## Configure Last.fm

Set your Last.fm API key and shared secret, then run the auth flow:

```sh
export LASTFM_API_KEY="..."
export LASTFM_SHARED_SECRET="..."
.build/release/scrobbler auth
```

The command opens Last.fm in your browser. Approve access, return to the terminal, and press Return.

The saved config lives at:

```text
~/.config/apple-music-lastfm-scrobbler/config.json
```

The config file is written with `0600` permissions because it contains the Last.fm shared secret and session key.

## Run

Foreground:

```sh
.build/release/scrobbler run
```

Check the current Apple Music track:

```sh
.build/release/scrobbler now
```

On first run, macOS may ask for Automation permission so the binary can control Music.app. Allow it, otherwise the scrobbler cannot read the current track.

## Run In The Background

Install and start a per-user `launchd` agent:

```sh
.build/release/scrobbler install-agent
```

Check status:

```sh
.build/release/scrobbler agent-status
```

Stop and remove the agent:

```sh
.build/release/scrobbler uninstall-agent
```

The generated plist is:

```text
~/Library/LaunchAgents/com.local.apple-music-lastfm-scrobbler.plist
```

Logs are written to:

```text
~/Library/Logs/com.local.apple-music-lastfm-scrobbler.log
~/Library/Logs/com.local.apple-music-lastfm-scrobbler.err.log
```

The plist points to the exact binary used for `install-agent`. If you move the repository or rebuild into a different path, run `uninstall-agent` and `install-agent` again.

## Commands

```text
scrobbler auth             Authorize Last.fm and save a session key
scrobbler run              Poll Apple Music and scrobble tracks
scrobbler now              Print the current Apple Music track
scrobbler install-agent    Install and start a launchd user agent
scrobbler uninstall-agent  Stop and remove the launchd user agent
scrobbler agent-status     Print launchd status for the user agent
scrobbler help             Print help
```

## Troubleshooting

If `now` prints `stopped`, either Music.app is not running, nothing is playing, or the track metadata is incomplete.

If Apple Music access fails, check:

```text
System Settings -> Privacy & Security -> Automation
```

Allow the terminal app or `scrobbler` binary to control Music.app.

If the background agent is running but nothing scrobbles, check:

```sh
tail -f ~/Library/Logs/com.local.apple-music-lastfm-scrobbler.err.log
tail -f ~/Library/Logs/com.local.apple-music-lastfm-scrobbler.log
```

If Last.fm rejects requests, run auth again:

```sh
.build/release/scrobbler auth
.build/release/scrobbler install-agent
```

## Development

Run tests:

```sh
swift test
```

Run from source:

```sh
swift run scrobbler now
swift run scrobbler run
```

## Privacy

This tool reads the currently playing Apple Music track metadata and sends it to Last.fm. It does not inspect other players. It stores Last.fm credentials locally in `~/.config/apple-music-lastfm-scrobbler/config.json`.

## License

MIT. See [LICENSE](LICENSE).
