# Contributing

Bug reports and small focused pull requests are welcome.

## Scope

This project is intentionally narrow:

- Apple Music on macOS is supported.
- Other players are not planned.
- The CLI should stay dependency-light and easy to audit.

## Development

```sh
swift test
swift build -c release
```

Use `swift run scrobbler now` to test Apple Music metadata access locally.

## Pull Requests

Before opening a pull request:

- Keep changes focused.
- Add or update tests for behavior changes.
- Update README or CHANGELOG when user-facing behavior changes.
- Do not commit Last.fm API keys, session keys, local config files, or logs.

## Reporting Bugs

Include:

- macOS version.
- Swift version from `swift --version`.
- Command you ran.
- Relevant log lines from `~/Library/Logs/com.local.apple-music-lastfm-scrobbler.err.log`.
- Whether Music.app was playing, paused, or stopped.
