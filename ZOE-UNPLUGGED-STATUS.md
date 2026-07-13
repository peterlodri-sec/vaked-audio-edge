# Zoé MTV Unplugged Import Status

## Completed ✅

1. **Soñé (MTV Unplugged)** — `https://audio.vaked.dev/stream/so-mtv-unplugged`
   - Duration: 3:52
   - Imported: 2026-07-13
   - Zero local bandwidth used (processed via CF Container)

## Remaining (13 tracks)

Script created: `import-zoe-unplugged.sh`

**Issue:** CF Worker returning 502 Bad Gateway on `/import` endpoint. First track succeeded, subsequent imports failing.

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

## Next Steps

1. Check CF Worker logs for `/import` errors
2. Verify CF Container running and accessible
3. Retry `./import-zoe-unplugged.sh` once worker stabilized
4. All imports run on CF infrastructure — no local bandwidth used

## Architecture

```
YouTube URL → CF Worker /import → CF Container (yt-dlp + ffmpeg) → R2 Storage (Opus)
```

Zero local machine bandwidth. All processing on Cloudflare edge.
