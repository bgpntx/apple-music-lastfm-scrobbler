# Security

## Supported Versions

Until tagged releases exist, only the current `main` branch is supported.

## Reporting A Vulnerability

Open a GitHub issue if the report does not contain secrets or private data.

Do not paste Last.fm API secrets, session keys, or full local config files into issues.

## Local Secrets

The scrobbler stores Last.fm credentials in:

```text
~/.config/apple-music-lastfm-scrobbler/config.json
```

The file is written with `0600` permissions. Treat it as secret material.
