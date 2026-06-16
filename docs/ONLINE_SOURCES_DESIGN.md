# 在线源能力设计文档（Online Sources）

> 目标：在 **MediaLib 现有架构**之上，**原生 Swift 补充**「在线源解析与管理」功能逻辑，
> 让 mac app 直接对接外部源（IPTV / VOD / 在线音乐），**不依赖** Movie Lite / Music Lite 的 Web API。
>
> 原则：以 mac app 当前架构为准，只做功能逻辑补充，不搬 Web 架构。

## 0. 背景与定位

- Movie Lite / Music Lite 本身只是「外部源聚合器」——它们拿的也是外部源（豆瓣、IPTV M3U、TVBox config、网易云/GD Studio 音乐源）。
- 因此 mac app 需要的不是这两个站点的 API，而是**它们底层用到的外部源类型 + 解析逻辑**，用 Swift 原生复刻。
- MediaLib 当前 `MediaSource` 仅支持 `local / emby / jellyfin / plex / smb / ftp`（见 `MediaSource.swift:160` `MediaSourceKind`）。**完全没有**在线点播 / 直播 / 在线音乐源的概念。
- 本设计为 MediaLib 新增三类「在线源」，复用现有 `MediaSource` 模型与 `media_sources` 表，通过 URL scheme 区分类别（与 emby:// 同模式）。

## 1. 现有架构关键事实（落点）

| 关注点 | 现状 | 落点 |
|---|---|---|
| 源模型 | `MediaSource`（id/name/**path**/mediaType/...），用 `path` 的 scheme 区分类别 | `Sources/MediaLibCore/Models/MediaSource.swift` |
| 源类别枚举 | `MediaSourceKind`：local/emby/jellyfin/plex/smb/ftp，由 `path.hasPrefix("emby://")` 推导 | `MediaSource.swift:122 sourceKind` |
| 媒体类型 | `MediaType`：movie/tvShow/anime/.../music | `MediaType.swift` |
| 源存储 | `media_sources` 表 + `SourceRepository` | `DatabaseManager.swift:380` |
| Schema 迁移 | `user_version` 递增式迁移，当前 **v18**，`currentSchemaVersion` | `DatabaseManager.swift:194 migrate()` |
| 远程连接器 | `RemoteConnectorProvider`（emby/jellyfin/plex）+ `EmbyService`/`PlexService` | `RemoteSyncModels.swift` / `App/*Service.swift` |
| 源管理 UI | `SourcesView` —— 添加/连接/列出源 | `Sources/MediaLib/Views/SourcesView.swift` |
| 播放入口 | libmpv（dlopen 运行时加载）+ AVFoundation | `App/LibMpvClient.swift` / `Views/PlayerView.swift` |

**核心复用决策**：新增在线源**沿用 `MediaSource` + `media_sources` 表**，用新的 URL scheme
（`iptv://`、`vod://`、`onlinemusic://`）注入 `path`，并扩展 `MediaSourceKind`。
源的「订阅配置」（M3U URL、VOD API endpoint、音乐 provider）存进 `path` 或新增的 JSON 配置列。

## 2. 三类在线源（来自 Lite 站点的实际外部源盘点）

### 2.1 IPTV 直播源（来自 Movie Lite `iptv_sources`）
- **输入形态**：M3U / M3U8 订阅 URL，或直接粘贴的 M3U 文本（`#EXTM3U` + `#EXTINF` + url）。
- **解析**：标准 M3U parser → 频道列表（name / group-title / tvg-logo / url）。
- **聚合**：同名频道多源聚合（换台≠切源，按 HTTPS/HLS 优先排序）——见 MEMORY「Movie Lite」既有约定。
- **播放**：HLS/HTTP 流直接喂 libmpv。

### 2.2 VOD 点播源（来自 Movie Lite VOD helpers）
- **输入形态**：
  - `json_api`：苹果 CMS V10 风格 JSON API（`?ac=detail&wd=关键词` → vod_play_url）。最常见、最易实现。
  - `tvbox_config`：TVBox 接口配置（sites 数组）。**仅支持 type=1（JSON）**，type=3（jar/spider）跳过（与 Movie Lite 同策略，见 server.py:1131）。
- **解析**：搜索 → 详情 → `parse_episodes`（`第1集$url#第2集$url`）→ 播放地址。
- **播放**：m3u8/mp4 直连喂 libmpv；需解析器的源（淘片/光速）标注「网页受限」。

### 2.3 在线音乐源（来自 Music Lite）
- **输入形态**：
  - 内置 provider：网易云（NeteaseCloudMusicApi 兼容）、GD Studio（`music-api.gdstudio.xyz`）。
  - 自定义 LX Music 兼容源（`music_sources` 表里的 URL）。
- **解析**：搜索（`/search`）→ 歌曲列表 → 播放地址（`/song_url`，多 provider fallback）→ 歌词（`/lyric` LRC）。
- **播放**：直链音频喂 libmpv/AVPlayer；歌词 LRC 解析复用现有 `LyricAlignmentService`。

> 注意：以上「来自 Lite」指的是**源类型与解析协议**，mac app 直接对接这些外部服务（网易云、GD Studio、M3U URL、CMS API），**不经过** Lite 站点。

## 3. 数据模型扩展

### 3.1 MediaSourceKind 扩展（`MediaSource.swift`）
```swift
public enum MediaSourceKind: String, Codable, Hashable {
    case local, emby, jellyfin, plex, smb, ftp   // 现有
    case iptv          // 新增：iptv://
    case vod           // 新增：vod://
    case onlineMusic   // 新增：onlinemusic://
}
```
`sourceKind` 计算属性增加 3 个 `hasPrefix` 分支。`displayName`/`systemImage` 同步补充。

### 3.2 源配置存储（最小侵入）
- **复用 `path` 列**：`iptv://<订阅URL编码>`、`vod://<endpoint编码>`、`onlinemusic://<provider>`。
- **新增配置列（migration v19）**：`media_sources.online_config TEXT`（JSON），存解析所需的结构化参数：
  ```json
  // IPTV
  {"subscriptionURL":"https://...","epgURL":null,"userAgent":null}
  // VOD
  {"kind":"json_api","apiBase":"https://.../api.php/provide/vod","name":"...","needsParser":false}
  {"kind":"tvbox_config","configURL":"https://...","onlyJSONSites":true}
  // OnlineMusic
  {"provider":"netease|gdstudio|custom","apiBase":"https://...","quality":"320"}
  ```
- 向后兼容：旧行 `online_config` 为 NULL，`sourceKind` 仍可由 path scheme 推导。

### 3.3 在线媒体条目（不入库扫描，按需查询）
在线源**不做本地全量扫描入库**（区别于 local/emby）。改为：
- IPTV：频道列表缓存（TTL，参考 MEMORY「Top250缓存3–5天」习惯，IPTV 频道 6–12h）。
- VOD / OnlineMusic：搜索即查询，结果走内存缓存（不持久化大量条目）。
- 收藏/播放记录：复用现有 `favorites` / `PlaybackMarkerRepository`，以「源ID + 远程ID」做 key。

## 4. Service 层（新增，仿 EmbyService）

| 文件 | 职责 | 关键方法 |
|---|---|---|
| `App/M3UParser.swift` | M3U/M3U8 文本 → 频道数组 | `parse(_ text:) -> [IPTVChannel]` |
| `App/IPTVSourceService.swift` | 拉订阅、解析、同名聚合、频道列表缓存 | `fetchChannels(source:)`、`resolvePlayable(channel:)` |
| `App/VODSourceService.swift` | CMS JSON API 搜索/详情/选集；TVBox config 解析(type=1) | `search(_:)`、`detail(_:)`、`episodes(_:)` |
| `App/OnlineMusicService.swift` | 网易云/GD Studio 搜索、播放地址 fallback、歌词 | `search(_:)`、`playURL(song:)`、`lyric(song:)` |

- 全部 `actor` 或 `@MainActor` 隔离，遵守 Swift 5.10 并发（避免之前踩的 captured-var-self 坑）。
- 网络层统一 `URLSession async/await`，复用现有 `RemoteCredentialStore` 存自定义源凭证（如有）。
- 失败策略：多 provider/多源 fallback，错误透出到 UI（参考 Music Lite playback cockpit 习惯）。

## 5. UI 层改动（`SourcesView` + 播放视图）

### 5.1 添加在线源
`SourcesView` 现有「连接远程服务器」入口旁增加：
- 「+ IPTV 订阅」：输入 M3U URL 或粘贴文本 → 校验 → upsert。
- 「+ 点播源」：选择 `json_api` / `tvbox_config`，填 endpoint/config URL。
- 「+ 在线音乐源」：选 provider（网易云/GD Studio/自定义）。

### 5.2 浏览/播放
- IPTV：频道网格（按 group-title 分组），点击→ libmpv 播放，失败快速换线路（MEMORY 约定）。
- VOD：搜索框→结果卡片→详情选集→播放。
- 在线音乐：复用现有 `MusicLibraryView` / `MusicPlayerView`，数据源切到在线 provider；歌词走 `LyricAlignmentService`。

### 5.3 侧栏
`ContentView` 的 `SidebarSelection` 增加在线源入口（或归入现有 VOD/IPTV/Music section）。

## 6. Schema 迁移（v19）

```swift
static let currentSchemaVersion = 19   // 18 → 19
// migrate(): if version < 19 { migrateToVersion19(); user_version = 19 }
private func migrateToVersion19() throws {
    try execute("ALTER TABLE media_sources ADD COLUMN online_config TEXT")
    // IPTV 频道缓存表
    try execute("""
    CREATE TABLE IF NOT EXISTS iptv_channels_cache (
      source_id TEXT, channel_id TEXT, name TEXT, group_title TEXT,
      logo TEXT, urls_json TEXT, updated_at TEXT,
      PRIMARY KEY(source_id, channel_id)
    )""")
}
```
`SourceRepository` 读写补 `online_config`；`MediaSource` 增 `onlineConfig: OnlineSourceConfig?`（Codable）。

## 7. 实施阶段与验收

### Phase 1 — 在线音乐源（最简单，先做）
- 模型扩展 + migration v19 + `OnlineMusicService`（网易云 + GD Studio）
- UI：添加音乐源、搜索、播放、歌词
- **验收**：真实搜索一首歌 → 播放出声 → 歌词滚动。

### Phase 2 — IPTV 直播源
- `M3UParser` + `IPTVSourceService` + 同名聚合 + 频道缓存表
- UI：添加 M3U 订阅、频道网格、libmpv 播放、换线路
- **验收**：导入一个公开 M3U → 频道列表 → 播一个 HLS 频道。

### Phase 3 — VOD 点播源（最复杂）
- `VODSourceService`（CMS JSON API 优先；TVBox type=1）
- UI：添加点播源、搜索聚合、选集、播放
- **验收**：配一个 CMS JSON API → 搜索 → 选集 → 播放。

## 8. 风险与约束

- **无本地 Swift 环境**：每阶段改动后 push → GitHub Actions 编译 → 验证 DMG（沿用现流程）。
- **Swift 5.10 严格并发**：新 Service 一律 actor/MainActor 隔离，避免 captured-var-self（已踩过）。
- **不做流代理**：与 Lite 站点一致，源直链交给客户端（libmpv）解析播放，mac app 不转发视频流。
- **TVBox type=3 (jar/spider)**：明确不支持，标注「网页受限」，与 Movie Lite 同策略。
- **法律/自用边界**：纯自用，外部源仅做解析与播放，不分发不缓存版权内容。

## 9. 不做的事（明确边界）

- ❌ 不搬 Movie/Music Lite 的 Python/Web 代码架构
- ❌ 不调用 Lite 站点的 HTTP API（mac app 直连外部源）
- ❌ 不做在线源的全量扫描入库（按需查询 + 轻缓存）
- ❌ 不代理/转码/落地视频流
