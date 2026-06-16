# self-media (MediaLib rebase)

Personal-use macOS media app. This repository was **rebased onto
[Again0521/MediaLib](https://github.com/Again0521/MediaLib)** — a native
SwiftUI macOS app with a libmpv-based player — replacing the earlier
lightweight `OpenClawMedia` prototype.

Why the rebase: the previous prototype was too thin to grow into the target
app (Emby / Plex / Jellyfin connectors, episode aggregation, word-by-word
lyrics, library health, offline cache). MediaLib already ships that
architecture, so we adopt it as the trunk and extend it.

## Architecture

- `Sources/MediaLibCore` — pure Foundation/AppKit/SQLite3 layer: models,
  services, and SQLite repositories (real DB persistence).
- `Sources/MediaLib` — the SwiftUI macOS app. libmpv is loaded at runtime via
  `dlopen` (no compile-time linkage); the player, remote connectors
  (`EmbyService`, `PlexService`), TMDB/Trakt/Last.fm, subtitle search and
  offline cache live here.
- `Sources/MediaLibChecks` — runnable assertion harness used as a CI gate.

## Build

CI builds an unsigned DMG on a macOS runner
(`.github/workflows/public-safety-and-build.yml`):

1. `brew install mpv ffmpeg` (libmpv + ffmpeg get bundled into the `.app`).
2. `scripts/medialib/package_dmg.sh` — `swift build -c release` + `.app`
   bundling + libmpv/ffmpeg embedding + DMG packaging.
3. On `main`, the DMG is published to the `latest` GitHub release.

Local macOS build:

```bash
brew install mpv ffmpeg
./scripts/medialib/package_dmg.sh   # produces dist/MediaLib.dmg
```

The Linux side has no Swift toolchain; `scripts/validate_medialib_structure.py`
asserts the architecture is intact before the macOS job runs.

## Planned extensions (this fork)

- Movie Lite (VOD) and Music Lite as `MediaSource` connectors, reusing the
  Emby/Plex connector pattern. Endpoint template in `config.example.json`.

## Attribution & license

Upstream app: [Again0521/MediaLib](https://github.com/Again0521/MediaLib).
Per upstream, this code is **for personal study and use**. Bundled libmpv,
ffmpeg and other third-party components follow their own licenses. Confirm the
relevant license terms before any redistribution or commercial use.
See `docs/MEDIALIB_UPSTREAM_README.md` for the upstream README.
