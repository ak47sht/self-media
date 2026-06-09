# Architecture decision — configurable sources and weak backend

Status: accepted for the first native Mac app direction.

## Decision

OpenClaw Media should preserve configurable media-source capability. The native app should not be just a fixed web-service client; it should become a local media cockpit that can point at multiple user-controlled sources while relying on a deliberately weak backend for aggregation and compatibility.

## Product interpretation

This app is a **weak-backend / strong-local-client** media app:

- The backend remains small: API facade, cache, normalization, compatibility with the existing web tools.
- The Mac app owns user experience: source management, route choice, external player handoff, local playback state, history/favorites, lyrics panel, keyboard shortcuts.
- The app should be useful even if the backend only exposes a few stable JSON endpoints.

## Why configurable sources matter

1. **User control**
   - IPTV/M3U/live channel sources change frequently.
   - Music providers and parsers may change.
   - A fixed-source app becomes stale quickly.

2. **Personal/self-hosted use**
   - Users may have private M3U lists, OpenList/Emby-like libraries, or different music providers.
   - These should live in local config, not in the public repo.

3. **Reduced VPS responsibility**
   - The VPS should not proxy video/audio traffic by default.
   - Local app can choose direct play or external-player handoff.

4. **Better iteration surface**
   - Source parser rules can evolve in the app or in lightweight backend endpoints without rewriting the UI.

## Boundary: app vs backend

### Keep in the Mac app

- Source configuration UI.
- Local source list, enable/disable, priority.
- Route selection and route health display.
- External player actions: IINA, VLC, copy URL.
- Local history/favorites/queue.
- Lyrics display and local now-playing state.
- Lightweight parsing of simple local/remote M3U files when no special headers/proxy are needed.
- Keyboard shortcuts and native playback controls.

### Keep in weak backend

- Existing `/api/iptv/channels` and `/api/iptv/channel` normalization.
- Existing `/api/search`, `/api/play-url`, `/api/lyrics` music API facade.
- Cache for slow upstream search/provider calls.
- Source normalization when it requires server-side files or scheduled refresh.
- Anything requiring credentials that should not live in the app bundle.
- Anything requiring CORS/proxy compatibility for the existing web tools.

### Avoid in v1

- Full account system.
- Public multi-user service posture.
- Server-side video/audio proxy by default.
- Heavy database sync.
- Watch-room/social/community features.
- Server-side offline downloads.

## Source model sketch

Types:

- `backendMovie`: existing self-hosted Movie Lite API.
- `backendMusic`: existing self-hosted Music Lite API.
- `iptvM3U`: local or remote M3U playlist.
- `openlist`: future personal library source.
- `aiImageProvider`: user-configured image generation provider (domain/base URL, API key in Keychain, model ID, request preset).
- `customParser`: future user-defined parser contract, disabled by default.

Fields:

- id
- name
- kind
- baseURL or fileURL
- enabled
- priority
- tags
- capabilities: search, liveTV, directPlay, lyrics, externalPlayerRecommended
- auth mode: none, header token, local-only credential reference, Keychain credential reference for provider API keys

Security:

- Source secrets stay in local config/keychain.
- Public repo contains only examples.
- UI should show host/protocol by default, not full secret-bearing URLs.

## Design consequence

The Settings page must be a first-class part of the app, not an afterthought. It needs:

- Source list.
- Enable/disable toggles.
- Priority/reorder affordance.
- Source type badges.
- “Test source” action.
- Safety copy: streams are direct-played locally; VPS does not proxy by default.

## Figma prompt addendum

Add to the Figma brief:

> Treat source configurability as a core feature. The app is a weak-backend/strong-local-client media cockpit. Include a Settings/Sources screen with local source cards, enable toggles, source priority, capability badges, and a clear “direct play / external player / backend normalized” distinction. Do not make the app look like a fixed webview wrapper.
