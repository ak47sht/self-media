# API contract

Public repo notes:

- This file documents the client-facing API shape only.
- Do not commit real domains, tokens, upstream source URLs, SQLite data, or VPS deployment paths.
- Configure real domains locally through `config.local.json`.

## Config

`config.local.json`:

```json
{
  "appName": "OpenClaw Media",
  "movieBaseURL": "https://movie.example.com/tools/movie-lite",
  "musicBaseURL": "https://music.example.com/tools/music-lite",
  "apiTimeoutSeconds": 15,
  "preferHTTPS": true,
  "allowInsecureLocalhost": false
}
```

## Movie / IPTV

### List channels

`GET {movieBaseURL}/api/iptv/channels`

Query params:

- `q`: optional channel search text.
- `group`: optional exact group name.
- `source`: optional exact source name.
- `show_limited`: `0` default returns browser-friendly HTTPS routes only; `1` includes HTTP/RTMP/etc.
- `refresh`: `1` forces source refresh.

Response:

```json
{
  "channels": [
    {
      "name": "CCTV-1",
      "group": "央视",
      "logo": "https://image.example/cctv1.png",
      "sourceName": "Example Source",
      "url": "https://stream.example/cctv1.m3u8",
      "playURL": "https://stream.example/cctv1.m3u8",
      "browserPlayable": true,
      "routes": [
        {
          "url": "https://stream.example/cctv1.m3u8",
          "playURL": "https://stream.example/cctv1.m3u8",
          "sourceName": "Example Source",
          "group": "央视",
          "label": "HTTPS / HLS",
          "browserPlayable": true
        }
      ],
      "detailPath": "/iptv/play?ch=..."
    }
  ],
  "count": 1,
  "groups": ["央视"],
  "errors": [],
  "showLimited": false
}
```

### Single channel

`GET {movieBaseURL}/api/iptv/channel?name=CCTV-1`

Optional:

- `show_limited=1`
- `refresh=1`

Response:

```json
{
  "channel": { "name": "CCTV-1", "routes": [] },
  "errors": []
}
```

## Music

### Search songs

`GET {musicBaseURL}/api/search?q=晴天`

Response:

```json
{
  "songs": [
    {
      "id": "228908",
      "source": "kuwo",
      "name": "晴天",
      "artist": "周杰伦",
      "album": "叶惠美",
      "cover": "https://image.example/cover.jpg",
      "duration": "269"
    }
  ],
  "count": 1,
  "cache": "hit",
  "ncm_cache": "hit"
}
```

### Play URL

`GET {musicBaseURL}/api/play-url?id=228908&source=kuwo&name=晴天&artist=周杰伦&duration=269&br=320kmp3`

Response:

```json
{
  "url": "https://audio.example/song.m4a",
  "provider": "25pan"
}
```

The service returns the upstream audio URL; the app should play it directly and should not proxy audio through the VPS.

### Lyrics

`GET {musicBaseURL}/api/lyrics?id=228908&source=kuwo&name=晴天&artist=周杰伦`

Response:

```json
{
  "text": "[00:01.00]第一句\n[00:02.50]第二句",
  "lines": [
    { "time": 1.0, "text": "第一句" },
    { "time": 2.5, "text": "第二句" }
  ]
}
```
