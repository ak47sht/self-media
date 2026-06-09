# Figma Make export analysis

Source zip: user-uploaded Figma Make export bundle (`个人网站设计方案 (2).zip`)

Figma link provided by user: https://www.figma.com/make/Gj03OPuxTXX5FTFoD7Gawx/

## Verdict

This export is valid and buildable. It is not a pure Figma node JSON export; it is a Figma Make React/Vite/shadcn code bundle.

It contains enough design information to translate the intended Mac app visual direction into SwiftUI:

- Mac-like desktop shell in `src/app/App.tsx`.
- Left sidebar with traffic-light controls, brand, quick search, module navigation.
- Modules for Movie, Music, and AI image generation.
- Dedicated preview pages for Dashboard, IPTV, Movie detail, Movie home, Music charts, Music player, and responsive layouts.
- Design system docs, tokens, page-layout docs, and roadmap docs.

## Build verification

Extracted to a temporary local inspection directory during analysis.

Commands run:

```bash
npm install --ignore-scripts --no-audit --no-fund
npm run build
```

Result:

```text
vite v6.3.5 building for production...
✓ 1602 modules transformed.
dist/index.html                   0.81 kB │ gzip:  0.49 kB
dist/assets/index-DKJkuu4m.css  123.52 kB │ gzip: 18.29 kB
dist/assets/index-BF0ZFw_v.js   206.05 kB │ gzip: 59.54 kB
✓ built in 8.23s
```

Warning only: `react-router@7.13.0` prefers Node >=20 while this VPS has Node 18. Build still succeeds.

## Key files

- `src/app/App.tsx`
  - Main desktop app shell.
  - Brand: `Nexus / Personal Suite`.
  - Sidebar width: 220px.
  - Dark translucent background: `rgba(8,8,16,0.98)`.
  - Native-like traffic lights.
  - Quick search affordance with `⌘K`.
  - Main modules:
    - Movie / 影视聚合
    - Music / 音乐中心
    - Image Gen / AI 生图
  - Extension placeholders:
    - RSS Reader
    - Quick Notes
    - Add Plugin

- `src/app/components/MovieModule.tsx`
  - Movie discovery/watchlist/IPTV/history tabs.
  - IPTV section and source affordance.
  - Useful for translating current Movie Lite + IPTV into native SwiftUI screens.

- `src/app/components/MusicModule.tsx`
  - Music search/player/lyrics/queue layout.
  - Useful for SwiftUI music pane and persistent player design.

- `src/app/components/ImageGenModule.tsx`
  - AI image generation screen.
  - Prompt, negative prompt, style presets, model picker, size picker, advanced settings, gallery.
  - Maps well to the newly added `aiImageProvider` source type.

- `src/app/pages/IPTVPreview.tsx`
  - IPTV desktop preview with channels, groups, qualities, source count.

- `src/app/pages/MovieDetailPreview.tsx`
  - Movie detail page with available sources, quality, status, provider, speed.

- Docs:
  - `DESIGN_SYSTEM.md`
  - `PAGE_LAYOUTS.md`
  - `DESIGN_SUPPLEMENT.md`
  - `ITERATION_ROADMAP.md`
  - `FIGMA_GUIDE.md`
  - `figma-tokens.json`
  - `VIEW_DESIGN.md`
  - `HOW_TO_VIEW_DESIGNS.md`

## What can be directly reused

Do not copy React code into the public SwiftUI repo as implementation. Use it as design reference.

Reusable as design inputs:

- Color tokens:
  - Primary purple: `#8b5cf6`
  - Accent cyan: `#06b6d4`
  - Dark shell surfaces around `#080810`, `#12121f`, `#171717`
  - Success/warning/error semantics from `DESIGN_SYSTEM.md`

- Layout:
  - Native desktop split layout.
  - 220px left sidebar.
  - Main panel modules.
  - Search/command palette affordance.
  - Module-specific content panes.

- Interaction model:
  - Sidebar navigation.
  - Persistent player for Music.
  - IPTV channel list + player detail.
  - AI image prompt + provider/model/settings + gallery.
  - Source/status badges.

## SwiftUI translation plan

Recommended next implementation targets in this repository:

1. Update `App.swift` visual shell to more closely match the Figma Make export:
   - Dark sidebar.
   - Traffic-light spacer/visual affordance.
   - Brand block.
   - Quick search row with `⌘K` hint.
   - Movie / Music / IPTV / Image Gen / Settings nav items.

2. Add design tokens in Swift:
   - `AppTheme` or `DesignTokens` with colors, radius, spacing, font sizes.

3. Add `ImageGenView` placeholder:
   - Prompt field.
   - Model/source selector.
   - Size/style controls.
   - Gallery placeholder.
   - Source/provider settings entry.

4. Refine source settings UI:
   - Use cards and badges matching Figma source/status language.
   - Show `aiImageProvider` with base URL, model, Keychain/API key placeholder.

5. Refine IPTV detail:
   - Channel list and source count/quality badges.
   - Player placeholder with “Open in IINA / Copy stream URL”.

## Important caveat

The export is still a React web prototype, not a native macOS SwiftUI design spec. It provides strong visual/layout guidance, but native implementation should preserve:

- SwiftUI native controls where they improve feel.
- AVPlayer/VLCKit direction for playback.
- Keychain for provider secrets.
- Weak-backend + strong-client architecture.
- No WebView shell.
