# Figma Make prompt — OpenClaw Media native Mac app

Build a high-fidelity Figma Make design for a native macOS app named **OpenClaw Media**.

## Product position

This is not a webview wrapper. It is a **weak-backend / strong-local-client** native media cockpit.

- Backend: small JSON API facade, normalization, cache, compatibility with existing lightweight web tools.
- Mac app: source management, direct playback, route selection, external player handoff, local history/favorites, lyrics, configurable providers.
- The VPS should not proxy video/audio traffic by default.
- User-controlled sources and provider configs are first-class features.

## Visual direction

Use a compact, premium native console style:

- Apple TV + Spotify + Raycast + Linear/Vercel density.
- Dark liquid-glass surfaces.
- Translucent panels, rounded 20–28px corners, subtle borders, layered blur.
- Dense but calm. No huge marketing hero sections.
- It should feel like a native macOS app dashboard, not a website.

Color tokens:

- Background: near black, blue-tinted.
- Surface: dark graphite / translucent glass.
- Primary action: Apple blue.
- Playing/healthy state: green.
- Limited/problem route: amber.
- Text: high-contrast white, secondary gray, muted gray.

Typography:

- SF Pro style.
- Compact labels.
- Strong section titles.
- Monospace only for endpoint/route snippets.

## Screens to create

Create at least 4 desktop frames, 1440×900:

### 1. IPTV browser / now tuning

Layout:

- Left sidebar: OpenClaw Media logo/title, IPTV, Music, Queue, Settings.
- Main panel: segmented mode picker, search field, filter chips, compact channel rows.
- Rows show: channel name, group/source, route count, playable status dot.
- Right detail panel: selected channel card, source/group, capability badges, route list.
- Route list should show `HTTPS`, `HLS`, `Limited`, `External player suggested` style badges.

Actions:

- Play locally.
- Open in IINA.
- Copy stream URL.
- Switch route.

### 2. Music browser / now playing

Layout:

- Same shell.
- Main list: search songs/artists, source chips, song rows.
- Right detail: album placeholder, song title, artist, provider source, player controls, lyrics preview.

Actions:

- Play.
- Queue.
- Lyrics panel.
- Source/provider selector.

### 3. Settings / Sources

This is a core screen, not a secondary afterthought.

Show source cards for:

- Movie Lite backend.
- Music Lite backend.
- Local IPTV/M3U playlist.
- Future OpenList/personal library.
- Future AI image provider.

Each source card should include:

- Enable/disable toggle.
- Priority/order indicator.
- Source kind badge.
- Endpoint summary, showing host only, not full secret URL.
- Capability badges: Backend normalized, Direct play locally, External player ready, Lyrics, Search, AI image generation.
- Test source button.

Add a safety/info panel:

> Secrets stay local. API keys are stored in Keychain. Streams direct-play locally by default; the VPS does not proxy media unless explicitly configured.

### 4. Provider configuration modal / sheet

Create a native macOS sheet for adding/editing a source or provider.

Fields:

- Name.
- Type: Movie backend, Music backend, IPTV/M3U, OpenList, AI image provider, Custom parser.
- Base URL/domain.
- API key field with Keychain storage indicator.
- Model ID for AI providers.
- Capabilities checkboxes.
- Test connection button.
- Save button.

For AI image provider, show example values:

- Base URL: `https://api.example.com/v1`
- Model: `nano-banana-pro-1k` or `grok-imagine-image-lite`
- Key storage: Keychain, never committed.

## Architecture hints to reflect in the design

- Configurable sources are the product moat.
- Keep raw URLs and secrets hidden by default.
- Route/source diagnostics should be accessible but not ugly.
- External player handoff should feel native and intentional.
- The app should distinguish:
  - Direct play locally.
  - Backend normalized.
  - External player fallback.
  - Provider/API request.

## Do not design

- Do not create a marketing landing page.
- Do not make it look like a generic admin dashboard.
- Do not make it a mobile app.
- Do not show public multi-user/social/watch-party features.
- Do not imply server-side video/audio proxying by default.
- Do not expose secret API keys in visible UI.

## Output expectations

Generate native-looking Figma frames with reusable components:

- Sidebar item.
- Search field.
- Filter chip.
- Media row.
- Source card.
- Capability badge.
- Route row.
- Provider config sheet.
- Primary/secondary buttons.

Use auto layout and consistent spacing tokens where possible.
