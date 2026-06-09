# Mac media app references — KVideo and MoonTVPlus

This note records what can be safely borrowed for OpenClaw Media without copying code or inheriting unwanted licensing/product baggage.

## Summary

Use these projects as **product and interaction references**, not as code bases.

- KVideo: useful reference for liquid-glass visual language, IPTV source/route UX, HLS playback ergonomics, TV-style navigation, and resilient search/loading states. License is MIT, but its Apple TV app is only a `SwiftUI + WKWebView` shell, which is not our target.
- MoonTVPlus: useful reference for feature taxonomy and power-user media workflows, but its local LICENSE is `CC BY-NC-SA 4.0`. Do not copy code/assets/styles into our public repo. Borrow concepts only.

## KVideo — borrowable ideas

Repo: `KuekHaoYang/KVideo`
License observed locally: MIT.
Stack: Next.js / React / Tailwind / hls.js, with Android TV and Apple TV webview shells.

### Good ideas for our native Mac app

1. **Liquid Glass direction**
   - Translucent panels.
   - Rounded 2xl surfaces.
   - Subtle inner glow/focus states.
   - Clear z-axis hierarchy.

2. **IPTV source and route UX**
   - Show route count at row level.
   - Hide long raw stream URLs by default.
   - Make route capability visible: HTTPS/HLS, HTTP limited, native playable, external-player suggested.
   - Group routes under one normalized channel instead of showing many duplicate channel names.

3. **Playback ergonomics**
   - Surface buffering/route failure as actionable states, not generic errors.
   - Support route switching from the player detail panel.
   - Eventually add keyboard shortcuts: Space/K play-pause, arrow seek/volume, F fullscreen, M mute.

4. **TV-style focus thinking**
   - Even on Mac, support predictable keyboard focus and large hit targets for couch/living-room use.
   - Keep active selection obvious.

5. **Search/loading**
   - Preserve partial results and show loading/progress instead of blank screens.
   - Let user cancel or retry slow source searches later if we add multi-source search.

### Do not copy

- The Apple TV/tvOS code is a WKWebView wrapper; our app should remain native SwiftUI + AVPlayer/VLCKit.
- Do not inherit web-only hls.js assumptions into native player architecture.
- Do not add proxy modes that make the VPS carry video traffic unless explicitly chosen later.

## MoonTVPlus — borrowable ideas

Repo: `mtvpls/MoonTVPlus`
License observed locally: CC BY-NC-SA 4.0.

### Good ideas for our roadmap

1. **External player handoff**
   - Offer “Open in IINA/VLC” for HTTP/RTMP/problematic streams.
   - This matches our constraint: the VPS should not proxy video traffic.

2. **Power-user media layers**
   - History / continue watching.
   - Favorites.
   - Queue.
   - Route/source diagnostics hidden behind a compact disclosure.

3. **Lyrics / comments / secondary overlays**
   - For music, lyrics should be a first-class native panel.
   - For movie/IPTV, secondary metadata should be optional and not crowd playback.

4. **Download/offline concepts**
   - Keep as a future idea only; do not add server-side download flows to this lightweight app now.

### Do not copy

- Do not copy code/assets/styles due to CC BY-NC-SA constraints and project-specific restrictions.
- Do not inherit public-service/social-sharing assumptions.
- Do not add database/account/community-room complexity to our first native Mac app.

## Recommended design synthesis for OpenClaw Media

### v0.2 current shell

- Left native sidebar.
- Main searchable list for IPTV/Music.
- Right now-playing/detail panel.
- Dark liquid-glass materials.
- Apple blue for primary actions, green only for “currently playing”.

### v0.3 next UI iteration

Add, in this order:

1. **Real selected-item detail loading**
   - IPTV route detail endpoint call.
   - Music play URL + lyrics call on selection.

2. **External player affordance**
   - “Open in IINA” and “Copy stream URL” actions for limited routes.
   - Show only host/protocol in normal UI.

3. **Keyboard shortcuts**
   - Search focus.
   - Play/pause.
   - Up/down selection.
   - Route switch.

4. **Local history/favorites**
   - Store locally only.
   - No account/server sync in v0.3.

5. **Player foundation**
   - Start with AVPlayer for music and HLS-compatible IPTV.
   - Evaluate VLCKit only for formats AVPlayer cannot handle well.

## Figma prompt addendum

When generating Figma designs, add this to the existing Figma brief:

> Borrow the “liquid glass” density and IPTV route hierarchy from KVideo, but do not design a web app or WKWebView shell. Borrow MoonTVPlus’s external-player and power-user media taxonomy, but keep the first version local, native, and lightweight. The right detail panel should make route switching and external-player fallback feel native and safe, not like a debug console.
