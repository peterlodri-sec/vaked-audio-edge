#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///
"""
vaked-audio CLI — stream, play, and import tracks from the edge.

Usage:
  audio list                    List available tracks
  audio play <slug>             Stream and play a track
  audio play                    Interactive picker
  audio import <url>            Import from YouTube (via CF Container)
           --title TEXT --artist TEXT [--album TEXT]
  audio status                  Worker health check

Env:
  AUDIO_HOST   Edge worker host (default: https://audio.vaked.dev)
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urljoin

type Response = dict | bytes

HOST = os.getenv("AUDIO_HOST", "https://audio.vaked.dev")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def req(path: str, method: str = "GET", **kwargs) -> Response:
    import requests

    url = urljoin(HOST, path)
    resp = requests.request(method, url, timeout=120, **kwargs)
    resp.raise_for_status()
    ct = resp.headers.get("Content-Type", "")
    if "json" in ct:
        return resp.json()
    return resp.content


def fmt_duration(sec: int) -> str:
    m, s = divmod(int(sec), 60)
    h, m = divmod(m, 60)
    match h:
        case 0:
            return f"{m}:{s:02d}"
        case _:
            return f"{h}:{m:02d}:{s:02d}"


def find_player() -> str | None:
    players = ("mpv", "ffplay", "vlc", "afplay")
    return next((p for p in players if shutil.which(p)), None)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def cmd_list():
    tracks = req("/tracks")
    if not tracks:
        print("No tracks available.")
        return

    print(f"\n{'SLUG':<50} {'DURATION':>10}  ARTIST")
    print("-" * 90)
    for t in tracks:
        slug = t["slug"]
        dur = fmt_duration(t["duration"])
        artist = t.get("artist", "—")
        print(f"{slug:<50} {dur:>10}  {artist}")
        print(f"  {t['title']}")
        print()


def cmd_play(slug: str | None = None):
    player = find_player()
    if not player:
        print("No audio player found. Install mpv or ffmpeg.")
        sys.exit(1)

    if not slug:
        tracks = req("/tracks")
        if not tracks:
            print("No tracks.")
            return
        print("\nTracks:")
        for i, t in enumerate(tracks):
            print(f"  [{i}] {t['slug']:<40} {fmt_duration(t['duration'])}  {t['title']}")
        try:
            idx = int(input("\nPick a track number: "))
            slug = tracks[idx]["slug"]
        except (ValueError, IndexError, KeyboardInterrupt, EOFError):
            print("Cancelled.")
            return

    stream_url = urljoin(HOST, f"/stream/{slug}")
    print(f"\n▶ Streaming: {slug}  (player: {player})")
    print("  Press Ctrl+C to stop.\n")

    try:
        if player == "mpv":
            # Pipe via curl to avoid mpv/ffmpeg User-Agent triggering CF WAF
            if shutil.which("curl"):
                _stream_via_curl_mpv(stream_url)
            else:
                subprocess.run(
                    ["mpv", "--no-video", "--ytdl=no", "--user-agent=Mozilla/5.0", "--msg-level=all=warn", stream_url],
                    check=False,
                )
        elif player == "ffplay":
            _stream_via_ffplay(stream_url)
        elif player == "vlc":
            subprocess.run(["vlc", "--intf", "dummy", "--play-and-exit", stream_url], check=False)
        elif player == "afplay" and shutil.which("ffmpeg"):
            _stream_via_ffmpeg_afplay(stream_url)
        else:
            subprocess.run([player, stream_url], check=False)
    except KeyboardInterrupt:
        print("\n⏹ Stopped.")


def _stream_via_ffplay(url: str):
    """ffplay audio-only mode."""
    subprocess.run(
        [
            "ffplay",
            "-vn",
            "-nodisp",
            "-autoexit",
            "-loglevel",
            "quiet",
            "-user_agent",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            url,
        ],
        check=False,
    )


def _stream_via_curl_mpv(url: str):
    """curl → fifo → mpv. Avoids CF WAF + stdin format detection issues."""
    with tempfile.TemporaryDirectory() as tmpdir:
        fifo = os.path.join(tmpdir, "stream.opus")
        os.mkfifo(fifo, 0o600)
        curl = subprocess.Popen(
            ["curl", "-sSL", "-H", "User-Agent: Mozilla/5.0", url, "-o", fifo],
        )
        subprocess.run(
            ["mpv", "--no-video", "--ytdl=no", "--msg-level=all=warn", fifo],
            check=False,
        )
        curl.kill()
        curl.wait()


def _stream_via_ffmpeg_afplay(url: str):
    """ffmpeg decoded → named pipe → afplay. Works on macOS."""
    with tempfile.TemporaryDirectory() as tmpdir:
        fifo = os.path.join(tmpdir, "stream.fifo")
        os.mkfifo(fifo, 0o600)
        ffmpeg = subprocess.Popen(
            ["ffmpeg", "-loglevel", "quiet", "-i", url, "-f", "au", fifo],
        )
        subprocess.run(["afplay", fifo], check=False)
        ffmpeg.wait()


def cmd_import(url: str, title: str | None = None, artist: str | None = None, album: str | None = None):
    print(f"\n⬇ Importing: {url}")
    print("  Metadata auto-detected from YouTube (title, artist).")
    print("  Runs entirely on Cloudflare — no bandwidth from your machine.")
    print("  (may take 1-3 minutes for long videos)\n")

    t0 = time.time()
    try:
        payload = {"url": url}
        if title:
            payload["title"] = title
        if artist:
            payload["artist"] = artist
        if album:
            payload["album"] = album
        result = req(
            "/import",
            method="POST",
            json=payload,
        )
        elapsed = time.time() - t0
        print(f"  Done in {elapsed:.0f}s")
        print(f"  Title:    {result.get('title', '?')}")
        print(f"  Slug:     {result.get('slug')}")
        print(f"  Duration: {fmt_duration(result.get('duration', 0))}")
        print(f"  Stream:   {HOST}/stream/{result.get('slug')}")
    except Exception as e:
        print(f"  Import failed: {e}")
        sys.exit(1)


def cmd_status():
    try:
        tracks = req("/tracks")
        print(f"  Host:   {HOST}")
        print(f"  Tracks: {len(tracks)}")
        for t in tracks:
            print(f"    • {t['slug']}  ({fmt_duration(t['duration'])})  {t['title']}")
    except Exception as e:
        print(f"  Worker unreachable: {e}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        prog="audio",
        description="vaked-audio CLI — stream, play, and import from the edge",
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list", help="List available tracks")
    play_p = sub.add_parser("play", help="Play a track")
    play_p.add_argument("slug", nargs="?", help="Track slug (omit for interactive picker)")

    import_p = sub.add_parser("import", help="Import from YouTube")
    import_p.add_argument("url", help="YouTube URL")
    import_p.add_argument("--title", help="Track title")
    import_p.add_argument("--artist", help="Artist name")
    import_p.add_argument("--album", help="Album name")

    sub.add_parser("status", help="Worker health check")

    args = parser.parse_args()

    if args.cmd == "list":
        cmd_list()
    elif args.cmd == "play":
        cmd_play(args.slug)
    elif args.cmd == "import":
        cmd_import(args.url, args.title, args.artist, args.album)
    elif args.cmd == "status":
        cmd_status()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
