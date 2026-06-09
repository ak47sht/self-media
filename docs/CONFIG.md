# Public configuration

This repository is designed to stay public. Do not commit real service domains,
API tokens, cookies, SQLite files, or VPS deployment paths.

## Local config

Copy the template:

```bash
cp config.example.json config.local.json
```

Then fill in your own domains locally:

```json
{
  "movieBaseURL": "https://movie.example.com/tools/movie-lite",
  "musicBaseURL": "https://music.example.com/tools/music-lite"
}
```

`config.local.json` is ignored by git.

## Runtime lookup order

The Swift client looks for config in this order:

1. `./config.local.json` next to the current working directory.
2. `~/Library/Application Support/OpenClawMedia/config.json`.
3. `config.example.json` bundled or next to the working directory as a harmless placeholder.

If no real config is present, the app shows setup guidance instead of trying to
contact private services.
