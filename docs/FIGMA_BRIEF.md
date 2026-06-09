# Figma brief — OpenClaw Media native Mac app v0.2

Purpose: give Figma/Figma Make enough product context to redesign the first native macOS client without seeing private domains or backend code.

## Product

OpenClaw Media is a lightweight native macOS app for two self-hosted media services:

- Movie / IPTV: browse channels, search CCTV/sports/news, play the best route directly.
- Music: search songs, play direct upstream audio URL, show synced lyrics, keep a local queue.

The public repo has only client code and API contracts. Real domains live in local config and must not appear in public design files.

## App personality

Target feel: **Apple TV + Spotify + Raycast**, but smaller and self-use focused.

- Native macOS, not a webview shell.
- Dark glass surfaces, compact sidebar, media-first detail pane.
- Data-dense enough for power use, but not a dashboard.
- Should feel like a small personal media cockpit.
- No marketing/landing-page feel.

## Primary screens

### 1. Setup / empty config

Shown when `config.local.json` is absent or still points to placeholder domains.

Core content:

- App title: OpenClaw Media
- Status: “需要配置 Movie/Music 服务域名”
- Three-step setup:
  1. Copy `config.example.json` to `config.local.json`
  2. Fill `movieBaseURL` and `musicBaseURL`
  3. Relaunch app
- Secondary note: public repo intentionally contains no real domains/tokens.

Design intent:

- Calm, reassuring, native settings-like.
- Use a large rounded card centered in the window.
- Keep copy short.

### 2. Home shell

Main app layout:

- Left sidebar:
  - Header/logo: OpenClaw Media
  - Nav items: IPTV, Music, Queue, Settings
  - Config status pill
- Content toolbar:
  - Segmented control: IPTV / Music
  - Search field
  - Refresh button
- Main content:
  - IPTV mode: compact channel rows/cards.
  - Music mode: song rows/cards.
- Right/detail panel:
  - Now playing card
  - Selected channel/song details
  - Lyrics/route list

Design intent:

- Default dark mode.
- macOS glass feel: translucent sidebar, soft material cards.
- Spotify-style green is allowed only for “playing” state; main accent should be Apple blue.
- Avoid heavy gradients; use subtle radial glow behind the player area.

### 3. IPTV browsing state

User task: quickly find a channel and play the best route.

Components:

- Search input with placeholder: `Search CCTV, sports, news…`
- Filter chips: All, CCTV, Sports, News, HTTPS only
- Channel row:
  - Channel name
  - Group/source
  - Browser/native playable badge
  - Route count
  - Primary Play button
- Detail panel:
  - Channel name
  - Best route URL host only, not full URL
  - Route list with labels: HTTPS/HLS, HTTP limited, RTMP limited

Important:

- Never show giant raw URLs by default. Show host + protocol; reveal full URL only in copy/debug affordance.
- HTTP/RTMP routes should feel “limited”, not broken.

### 4. Music search state

User task: search and play a song directly.

Components:

- Search input with placeholder: `Search songs, artists…`
- Song row:
  - Title
  - Artist/album
  - Source badge
  - Duration
  - Play button
- Detail panel:
  - Now playing title/artist
  - Playback controls
  - Queue preview
  - Lyrics scroll

Important:

- The app receives a direct upstream audio URL from `/api/play-url`; do not imply the VPS proxies audio.
- Lyrics should look native and readable, not like a terminal dump.

## Visual tokens

Use SF system fonts.

Colors:

- App background: `#0B0D10`
- Sidebar material: `rgba(22, 24, 28, 0.72)`
- Primary surface: `#14171D`
- Elevated surface: `#1B1F27`
- Hairline: `rgba(255,255,255,0.08)`
- Primary text: `#F5F7FA`
- Secondary text: `#A8B0BD`
- Muted text: `#697180`
- Apple blue/action: `#0A84FF`
- Playing green: `#30D158`
- Warning amber: `#FFD60A`

Typography:

- Large title: 28 / semibold / tight
- Section title: 15 / semibold
- Body: 13 / regular
- Caption: 11 / medium
- Mono/debug: SF Mono 11

Shape:

- Sidebar/window cards: 20px radius
- Small cards/rows: 14px radius
- Buttons/chips: 999px radius
- Hairline border: 1px

Spacing:

- Window padding: 16px
- Sidebar width: 240px
- Detail panel width: 320px
- Row height: 64–76px
- Base gap: 8px / 12px / 16px

## Interaction notes

- Rows hover with subtle surface lift.
- Current playing row gets green dot + slight border.
- Primary Play button appears on row hover and is always visible in detail panel.
- Search should be the dominant control in toolbar.
- Config/setup errors should be explicit, not hidden.

## Figma output requested

Please create frames:

1. `01 Setup — missing config`
2. `02 IPTV — channel browsing`
3. `03 Music — search results`
4. `04 Player detail — lyrics/queue`

And components:

- Sidebar nav item
- Toolbar search field
- Filter chip
- IPTV channel row
- Music song row
- Now playing card
- Route badge
- Config status pill

## Constraints

- Public-safe: do not include real domains, real tokens, private hostnames, or internal filesystem paths.
- Use placeholder domains only: `movie.example.com`, `music.example.com`.
- Keep routes compatible with SwiftUI implementation; avoid web-only patterns.
- Prefer macOS native affordances over custom web dashboard chrome.
