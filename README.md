# OpenClaw Media

Native macOS media client for configurable Movie Lite and Music Lite style APIs.

This repository is intentionally public-safe:

- No real domains.
- No tokens.
- No SQLite data.
- No private VPS deployment paths.
- No copied source from unclear-license reference projects.

## Configure locally

```bash
cp config.example.json config.local.json
```

Edit `config.local.json` with your own service domains:

```json
{
  "movieBaseURL": "https://movie.example.com/tools/movie-lite",
  "musicBaseURL": "https://music.example.com/tools/music-lite"
}
```

`config.local.json` is ignored by git.

## Current scope

- SwiftUI macOS app skeleton.
- Config loader with placeholder/setup mode.
- Client models for IPTV channels, music search, play URLs, and lyrics.
- API client for:
  - `GET /api/iptv/channels`
  - `GET /api/iptv/channel`
  - `GET /api/search`
  - `GET /api/play-url`
  - `GET /api/lyrics`

## Build

On macOS:

```bash
swift build
```

The GitHub Actions workflow runs:

1. Public-safety scan on Ubuntu.
2. Swift build on macOS.

## Docs

- [Config](docs/CONFIG.md)
- [API contract](docs/API_CONTRACT.md)
- [Figma brief](docs/FIGMA_BRIEF.md)
- [Figma Make prompt](docs/FIGMA_MAKE_PROMPT.md)
- [Figma Make export analysis](docs/FIGMA_MAKE_EXPORT_ANALYSIS.md)
- [Mac media app references](docs/MEDIA_APP_REFERENCES.md)
- [Configurable sources](docs/CONFIGURABLE_SOURCES.md)
- [Decisions](docs/DECISIONS.md)
- [Open-source spike](docs/OPEN_SOURCE_SPIKE.md)
