# OpenClaw Media — 90% Completion Implementation Plan

> **For Hermes:** Execute phase by phase. Each phase has Swift code changes + validation updates.
> Verify: `python3 scripts/public_safety_check.py && python3 scripts/validate_source_config.py` after each phase.
> Final gate: push to `main`, GitHub Actions macOS build must pass and produce DMG.

**Goal:** Transform OpenClaw Media from a working skeleton (~35%) into a usable native macOS media cockpit (~90%).

**Architecture:** Split the 1611-line `App.swift` monolith into focused files under `Sources/OpenClawMedia/`.  
Add VOD search→detail→play, local persistence (favorites/history/queue), source CRUD, keyboard shortcuts,
playback error handling, and route auto-fallback — all client-side, no new backend dependencies.

**Tech Stack:** SwiftUI, AVPlayer, SPM, macOS Keychain, UserDefaults for local persistence.

**Validation Layer:** Because no Swift compiler is available on the Linux dev machine, each phase's
correctness is verified by extending `scripts/validate_source_config.py` with feature-specific string
assertions that CI's `swift build` confirms compiles.

---

## File Split (Phase 1 prep — done with Phase 1)

Current monolith `App.swift` (1611 lines, 69973 bytes) → split into:

```
Sources/OpenClawMedia/
├── App.swift                    # @main + ContentView (~60 lines)
├── Models/
│   ├── APIModels.swift          # existing IPTV/Music/AI models
│   ├── VODModels.swift          # NEW: VOD search, detail, play models
│   ├── StorageModels.swift      # NEW: Favorites, History, Queue, Playlist
│   └── Enums.swift              # extracted: MediaMode, SidebarSelection
├── Services/
│   ├── MediaAPI.swift           # existing API client + VOD endpoints
│   ├── PlaybackManager.swift    # enhanced: error handling, auto-fallback
│   ├── LocalStore.swift         # NEW: UserDefaults persistence
│   ├── SourceManager.swift      # NEW: CRUD for sources
│   └── VODService.swift         # NEW: TVBox search/detail/play resolution
├── Views/
│   ├── ContentView.swift        # extracted from App.swift
│   ├── Sidebar.swift            # extracted
│   ├── MovieDashboard.swift     # extracted
│   ├── IPTVView.swift           # extracted
│   ├── MusicView.swift          # extracted
│   ├── VODView.swift            # NEW: search → detail → play
│   ├── ImageGenView.swift       # extracted
│   ├── SettingsView.swift       # extracted
│   ├── SourcesSettings.swift    # extracted
│   ├── DetailPanel.swift        # extracted
│   ├── PlayerSurface.swift      # extracted
│   └── SharedComponents.swift   # extracted: Theme, badges, cards, etc.
├── Config.swift                 # existing
├── SourceConfig.swift           # existing
├── LocalSourceParsing.swift     # existing
└── KeyboardHandler.swift        # NEW: keyboard shortcuts
```

---

## Phase 1: File Split + VOD Search → Detail → Play

**Goal:** The user can import TVBox/VOD sources, search titles, view details, select episodes, and play.

### Task 1.1: Create VODModels.swift
- `VODSearchRequest`, `VODSearchResult`, `VODSearchResponse`
- `VODEpisode`, `VODDetailItem`, `VODDetailResponse`
- `VODPlayResponse` — resolved stream URL
- Coding keys and Codable conformance

### Task 1.2: Extend MediaAPI with VOD endpoints
- `searchVOD(source: VODSource, query: String) -> VODSearchResponse`
- `vodDetail(source: VODSource, id: String) -> VODDetailResponse`
- `vodPlay(source: VODSource, flag: String, id: String) -> VODPlayResponse`
- TVBox standard API format: `{api}?wd={query}`, `{api}?ac=detail&ids={id}`, `{api}?ac=play&flag={flag}&id={id}`

### Task 1.3: Create VODService.swift
- `VODSearchManager`: orchestrate search across sources, deduplicate, sort
- Handle TVBox JSON response parsing (nested `list`/`videos` arrays)

### Task 1.4: Create VODView.swift
- Search bar + source picker
- Grid/list of results (title, year, poster placeholder)
- Detail sheet: description, episodes grouped by flag/source
- "Play" action: resolve URL → AVPlayer or external player
- Loading/empty/error states

### Task 1.5: File Split
- Move Enums, Views, Services into subdirectories
- Keep App.swift clean with just @main + ContentView
- Ensure all imports still work (Swift finds all .swift files recursively)

### Task 1.6: Update validation scripts
- Add VOD model/service/view checks to `validate_source_config.py`

---

## Phase 2: Playback Stability

**Goal:** Route auto-fallback, error states, loading indicators.

### Task 2.1: Enhanced PlaybackManager.swift
- Listen for `AVPlayerItem.status`, `.error`, `.timeControlStatus`
- Track `playbackState`: idle / loading / playing / paused / stalled / error
- On error: try next route automatically (up to 3)
- Show reason for failure to user
- `@Published` properties for UI binding

### Task 2.2: Auto-fallback logic
- In `PlaybackRouteResolver`, add `fallbackRoutes` method
- In `NativePlaybackManager`, on error callback auto-try next
- Expose `currentRouteIndex` and `totalRoutes`
- User can manually switch routes in detail panel

### Task 2.3: UI states
- Loading spinner during buffering
- Error banner with action ("Try next route", "Copy URL", "Open in IINA")
- Connection quality indicator

---

## Phase 3: Local Persistence (Favorites/History/Queue)

**Goal:** Favorites, recent plays, and queue survive app restarts.

### Task 3.1: Create StorageModels.swift
- `FavoriteItem`: id, type (channel/song/vod), title, subtitle, date, thumbnail
- `HistoryItem`: same + playCount, lastPlayed
- `QueueItem`: same + order position
- Codable, Identifiable

### Task 3.2: Create LocalStore.swift
- UserDefaults-backed: favorites, history, queue
- `addFavorite()`, `removeFavorite()`, `isFavorite()`, `getFavorites()`
- `addToHistory()`, `getRecentHistory(limit:)`, `clearHistory()`
- `enqueue()`, `dequeue()`, `reorder()`, `clearQueue()`
- ObservableObject for SwiftUI binding

### Task 3.3: Integrate into UI
- Detail panel: favorite toggle (star/heart)
- Sidebar Queue: show queue contents, reorder, play next
- History panel: recent plays with "play again"
- Auto-add to history on play

### Task 3.4: Movie dashboard uses real data
- "Continue watching" from history
- "Favorites" section
- Replace hardcoded placeholders

---

## Phase 4: Source Management

**Goal:** Users can add, edit, delete, and test sources.

### Task 4.1: Create SourceManager.swift
- `@Published var sources: [MediaSourceConfig]`
- `addSource(kind:, name:, url:)`
- `removeSource(id:)`
- `updateSource(id:, fields:)`
- `testSource(id:) -> Bool`
- Persist to config (merge with AppConfig)
- Load from config on init

### Task 4.2: Rewrite SourcesSettingsView
- "Add source" button → sheet with kind picker, URL field, name
- Per-source: enable toggle, edit, delete, "Test connection"
- Source type badges
- Re-order (priority up/down buttons)
- Capability display

### Task 4.3: Wire into config persistence
- Sources saved alongside AppConfig
- On save → reloadIdentity triggers view rebuild
- AI provider source special-cased (uses Keychain)

---

## Phase 5: Keyboard Shortcuts + Polish

**Goal:** Professional media-app keyboard shortcuts and playback controls.

### Task 5.1: Create KeyboardHandler.swift
- `Space` / `K` → play/pause
- `←` `→` → seek ±10s
- `↑` `↓` → volume ±10%
- `F` → fullscreen
- `M` → mute
- `Cmd+K` → focus search
- `Cmd+F` → toggle favorites
- `Cmd+Q` → quit (macOS default, don't override)
- `Esc` → exit fullscreen / close detail

### Task 5.2: Playback controls UI
- Seek bar (Slider with time labels)
- Volume slider
- Fullscreen toggle button
- Now-playing info bar

### Task 5.3: Image Gen improvements
- b64_json display
- Save to file
- Multi-result gallery
- Copy image to clipboard

### Task 5.4: M3U import improvements
- Progress during playlist fetch/parse
- Error on malformed M3U
- Group filtering actually works
- Channel count in sidebar

---

## Phase 6: Validation Complete

Update `scripts/validate_source_config.py` with tests covering all new features:

- VOD models and API methods
- LocalStore methods
- SourceManager methods
- Keyboard shortcuts presence
- Favorites/history/queue UI elements
- Playback error handling
- All new file existence

---

## Phase 7: CI Verification

- Push all commits to `main`
- GitHub Actions `public-safety-and-build` workflow must pass
- DMG artifact must be produced
- Fix any compilation errors (fetch macOS job logs, fix, push)

---

## Verification Checklist per Phase

- [ ] `python3 scripts/public_safety_check.py` passes
- [ ] `python3 scripts/validate_source_config.py` passes (after extending)
- [ ] `git diff --stat` shows expected changes
- [ ] Commit message describes the phase
- [ ] (Phase 7 only) GitHub Actions macOS build passes
