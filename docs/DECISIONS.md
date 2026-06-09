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
