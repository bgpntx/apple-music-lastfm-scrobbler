# GitHub Setup

Use these steps when publishing the repository for the first time.

## 1. Review Secrets

Before committing, make sure no local credentials are present:

```sh
git status --short
git diff --cached
```

Do not commit:

- Last.fm API keys.
- Last.fm shared secrets.
- Last.fm session keys.
- Local `config.json` or `state.json`.
- Local logs.

## 2. Commit

```sh
git add .
git commit -m "Initial Apple Music Last.fm scrobbler"
```

## 3. Create GitHub Repository

With GitHub CLI:

```sh
gh repo create apple-music-lastfm-scrobbler --public --source=. --remote=origin --push
```

Or create an empty repository in the GitHub UI, then:

```sh
git remote add origin git@github.com:<owner>/apple-music-lastfm-scrobbler.git
git branch -M main
git push -u origin main
```

## 4. Check CI

After pushing, confirm the GitHub Actions workflow passes:

```text
Actions -> CI
```

The workflow runs `swift test` and `swift build -c release` on macOS.

## 5. Suggested Repository Settings

- Protect `main` after the first push.
- Require the `CI / Swift tests` check before merging pull requests.
- Disable wiki unless you plan to use it.
- Add topics: `lastfm`, `scrobbler`, `apple-music`, `macos`, `swift`.
