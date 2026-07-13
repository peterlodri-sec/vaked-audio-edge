# vaked-audio-edge

[![CI](https://github.com/peterlodri-sec/vaked-audio-edge/actions/workflows/ci.yml/badge.svg)](https://github.com/peterlodri-sec/vaked-audio-edge/actions/workflows/ci.yml)
[![Python](https://img.shields.io/badge/python-3.12+-00d4ff.svg)](https://python.org)

Cloudflare edge audio streaming + YouTube import — Python CLI + macOS menu bar app.

## Features

- **CLI**: Stream, play, list tracks from edge worker
- **macOS app**: Menu bar controls, auto-start LaunchAgent
- **Import**: YouTube → Opus via CF Container (no local bandwidth)
- **Stack**: Cloudflare Workers, R2 storage, Container for yt-dlp + ffmpeg

## Usage

```bash
# CLI (uv run / standalone)
audio list                      # List tracks
audio play <slug>               # Stream track
audio play                      # Interactive picker
audio import <youtube-url>      # Import from YouTube
audio status                    # Worker health

# macOS app
open AudioEdge.app              # Menu bar player
```

## Configuration

```bash
export AUDIO_HOST=https://audio.vaked.dev    # Edge worker URL (default)
export MPV_PATH=/opt/homebrew/bin/mpv        # macOS app mpv path (fallback)
```

## Development

```bash
git clone https://github.com/peterlodri-sec/vaked-audio-edge.git
cd vaked-audio-edge

# Lint + format
uv run --with ruff ruff check cli.py
uv run --with ruff ruff format cli.py

# Build macOS app
swiftc audio-edge.swift -o AudioEdge.app/Contents/MacOS/AudioEdge
```

## Architecture

```
┌─────────────────┐
│   CF Worker     │  TypeScript + Hono
│   worker.ts     │  /tracks, /stream/:slug, /import
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   R2 Storage    │  Opus audio files
│   bucket/       │  metadata.json
└─────────────────┘
         │
         ▼
┌─────────────────┐
│  CF Container   │  yt-dlp + ffmpeg
│  /import POST   │  YouTube → Opus (on-demand)
└─────────────────┘
```

## License

MIT
