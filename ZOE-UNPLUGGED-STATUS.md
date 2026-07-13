# Zoé MTV Unplugged Import Status

## Status

**1/14 tracks imported** — CF Worker `/import` returning 502 Bad Gateway

### Completed ✅

1. **Soñé (MTV Unplugged)** — `https://audio.vaked.dev/stream/so-mtv-unplugged`

### Remaining (13 tracks)

**Tools ready:**
- `batch-import.py zoe-unplugged-tracks.txt` — easiest, retry logic built-in
- `import-zoe-unplugged.sh` — bash version with retry

**Issue:** CF Worker `/import` endpoint 502 Bad Gateway after first import

**Tracks to import:**
- Labios Rotos (MTV Unplugged)
- Luna (MTV Unplugged)
- Nada (MTV Unplugged)
- Nunca (MTV Unplugged)
- No Me Destruyas (MTV Unplugged)
- Paula (MTV Unplugged)
- Poli/Love (MTV Unplugged)
- Veneno (MTV Unplugged)
- Vía Láctea (MTV Unplugged)
- Sombras (MTV Unplugged)
- Dead (MTV Unplugged)
- Infinito (MTV Unplugged)
- Últimos Días (MTV Unplugged)

## Import Tools (Ready)

### Batch Import (Recommended)
```bash
python3 batch-import.py zoe-unplugged-tracks.txt
```
- Auto-retry on failures (3 attempts)
- Progress tracking
- Tab-separated format: `URL [TAB] title [TAB] artist [TAB] album`
- Supports stdin: `cat urls.txt | python3 batch-import.py`

### Shell Script
```bash
./import-zoe-unplugged.sh
```

### Single Track
```bash
python3 cli.py import <youtube-url> --title "Track" --artist "Artist"
```

## Next Steps

1. Fix CF Worker `/import` endpoint (check logs, Container health)
2. Run: `python3 batch-import.py zoe-unplugged-tracks.txt`
3. All processing on CF edge — zero local bandwidth

## Architecture

```
YouTube URL → CF Worker /import → CF Container (yt-dlp + ffmpeg) → R2 Storage (Opus)
```

Zero local machine bandwidth. All processing on Cloudflare edge.
