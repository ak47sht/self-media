# Decisions

## 2026-06-09 — Fresh SwiftUI app over direct fork

Open-source spike inspected several IPTV/Music candidates.

Decision: create a fresh `OpenClaw Media.app` and use open-source projects as architecture references only.

Reasons:

- Useful candidates had no clear GitHub license metadata / no LICENSE file.
- IPTV projects carried ads, iCloud, tvOS/iOS, EPG, VOD, and provider baggage.
- Music projects were tied to YouTube/Tidal/PythonService or NetEase bridge.
- Our app needs to connect to configurable Movie Lite / Music Lite APIs.

References:

- IPTV/player architecture: `lesnerd/easy-ip-tv`, `htutuncu/Pars-Player`
- Music UX/player architecture: `ShubhamPP04/Izzy`, `zeyugao/MusicBox`

## 2026-06-16 — Rebase onto Again0521/MediaLib

The fresh `OpenClawMedia` prototype was too thin to grow into the target app
(Emby/Plex/Jellyfin connectors, episode aggregation, word-by-word lyrics,
library health, offline cache) — limited by an under-built base architecture.

Decision: **rebase the trunk onto [Again0521/MediaLib](https://github.com/Again0521/MediaLib)**
(native SwiftUI + libmpv player + SQLite repository layer) and extend it,
rather than keep building the prototype. Personal use only; not for
redistribution/commercial use (upstream reserves rights).

Considered but rejected: `ShukeBta/MediaStationGo` — a Go/React self-hosted
Emby-alternative backend. Its heavy-backend architecture conflicts with the
"thin backend, strong local client, local-first" principle. Borrow feature
ideas only (download-to-library pipeline, Emby-protocol compatibility as a
source, AI recommendations).

Migration shape:
- Imported MediaLib `Sources/` (MediaLibCore + MediaLib app + MediaLibChecks).
- Reconstructed `Package.swift` (upstream shipped source + DMG only, no manifest).
- Build tooling under `scripts/medialib/`; CI brews mpv/ffmpeg and runs
  `package_dmg.sh` on a macOS runner.
- Pruned obsolete OpenClawMedia-era prototype/Figma/API docs.

Next: add Movie Lite (VOD) and Music Lite as `MediaSource` connectors, reusing
the Emby/Plex connector pattern.
