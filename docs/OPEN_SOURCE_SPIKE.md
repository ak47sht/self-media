# OpenClaw Media macOS App open-source base spike

Date: 2026-06-09

## Environment limitation

- The current development host cannot compile native macOS apps.
- macOS build should run on a Mac or GitHub Actions macOS runner.

## Candidates inspected

### IPTV / Movie

#### `lesnerd/easy-ip-tv`

- Repo: https://github.com/lesnerd/easy-ip-tv
- License: GitHub API says `None`; no clear LICENSE file found. README/license badge is not sufficient for safe redistribution.
- Platforms: macOS, iOS, tvOS.
- Dependencies: `vlckit-spm`, Google Mobile Ads.
- Architecture:
  - Player supports AVPlayer for HLS and VLC for non-HLS/VOD.
  - VLC controller includes network caching, HTTP reconnect, subtitle handling.
  - Has M3U parser tests, player logic tests, EPG overlay, VOD/live models.
  - Has GitHub Actions build/release workflows.
- Fit:
  - Best technical reference for IPTV/player behavior.
  - Too much product baggage for a tiny app: ads, iCloud/AppStorage, multi-platform/tvOS, EPG/VOD/download complexity.
  - License unclear, so avoid direct fork for anything redistributable.

#### `htutuncu/Pars-Player`

- Repo: https://github.com/htutuncu/Pars-Player
- License: None found.
- Platform: macOS.
- Dependencies: VLCKit.
- Architecture:
  - Very small SwiftUI macOS app.
  - Loads M3U file/URL and parses channels.
  - Wraps VLCMediaPlayer and NSViewRepresentable.
- Fit:
  - Good tiny prototype/reference.
  - UI and state management are too thin; no real API/data abstraction, no queue/favorites/route scoring.
  - License unclear.

#### AerioTV-style large IPTV apps

- Large IPTV/VOD/EPG/Xtream-style apps are too broad and often not macOS-first.
- Not recommended as a direct base.

### Music

#### `ShubhamPP04/Izzy`

- Repo: https://github.com/ShubhamPP04/Izzy
- License: None found.
- Platform: macOS.
- Architecture:
  - Strong playback manager: AVPlayer, queue manager, Now Playing/remote commands, stream URL caching, next/previous handling.
  - Search/cache layer exists, but tied to provider-specific services.
  - Mini player/global hotkey infrastructure exists.
- Fit:
  - Best music UX reference.
  - Direct fork would require replacing provider-specific services with our configurable API.
  - License unclear, so avoid direct redistribution.

#### `zeyugao/MusicBox`

- Repo: https://github.com/zeyugao/MusicBox
- License: None found.
- Platform: macOS.
- Architecture:
  - Strong native player: AVPlayer, smart lyrics, progressive cache, remote command center.
  - NetEase bridge deeply integrated.
  - Has GitHub Actions and DMG creation script.
- Fit:
  - Excellent reference for lyrics/cache/player internals.
  - Too coupled to NetEase-style internals for a quick fork.

#### `Mac-XK/KMusic`

- Repo: https://github.com/Mac-XK/KMusic
- License: None found.
- Local inspection showed provider/source files, not a reusable Swift client app base.
- Fit: not usable as app base.

## Recommendation

Do not direct-fork any candidate as the official base because useful candidates have unclear/no GitHub license metadata. Create our own app and copy patterns, not code.

Recommended implementation path:

1. Create a small new SwiftUI macOS project.
2. IPTV module:
   - Use AVPlayer for HTTPS/HLS.
   - Add VLC fallback later only if needed.
   - Prefer backend channel/routes API instead of app-side M3U parsing.
3. Music module:
   - Use AVPlayer playback manager, queue, Now Playing, mini player.
   - Use backend Music API for search/play URL/lyrics.
4. Build/distribution:
   - Add GitHub Actions macOS workflow for unsigned app/DMG artifact.
   - For public signed distribution, use Apple Developer ID signing + notarization.

## Backend API needed

Movie/IPTV:

- `GET /api/iptv/channels`
- `GET /api/iptv/channel?name=CCTV16`

Music:

- `GET /api/search?q=...`
- `GET /api/play-url?id=...`
- `GET /api/lyrics?id=...`
