#!/usr/bin/env python3
"""Batch import URLs from file or stdin. Zero local bandwidth."""
import argparse
import sys
import subprocess
import time

def import_track(url: str, title: str = "", artist: str = "", album: str = "", max_retries: int = 3):
    """Import with retry logic."""
    cmd = ["python3", "cli.py", "import", url]
    if title:
        cmd.extend(["--title", title])
    if artist:
        cmd.extend(["--artist", artist])
    if album:
        cmd.extend(["--album", album])
    
    for attempt in range(1, max_retries + 1):
        try:
            subprocess.run(cmd, check=True)
            return True
        except subprocess.CalledProcessError as e:
            if attempt < max_retries:
                print(f"  Retry {attempt}/{max_retries} after 5s...")
                time.sleep(5)
            else:
                print(f"  ✗ Failed after {max_retries} attempts")
                return False
    return False

def parse_line(line: str) -> dict:
    """Parse: URL [title] [artist] [album]"""
    parts = line.strip().split("\t")
    return {
        "url": parts[0],
        "title": parts[1] if len(parts) > 1 else "",
        "artist": parts[2] if len(parts) > 2 else "",
        "album": parts[3] if len(parts) > 3 else "",
    }

def main():
    parser = argparse.ArgumentParser(description="Batch import tracks (zero local bandwidth)")
    parser.add_argument("file", nargs="?", help="File with URLs (or stdin if omitted)")
    parser.add_argument("--artist", help="Default artist for all tracks")
    parser.add_argument("--album", help="Default album for all tracks")
    args = parser.parse_args()
    
    source = open(args.file) if args.file else sys.stdin
    
    print("Batch import — all processing on Cloudflare\n")
    
    success_count = 0
    fail_count = 0
    
    for line in source:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        
        track = parse_line(line)
        artist = track["artist"] or args.artist or ""
        album = track["album"] or args.album or ""
        
        print(f"Importing: {track['title'] or track['url']}")
        if import_track(track["url"], track["title"], artist, album):
            success_count += 1
        else:
            fail_count += 1
        print()
    
    if source != sys.stdin:
        source.close()
    
    print(f"✓ {success_count} imported, {fail_count} failed")
    print("  Stream at: https://audio.vaked.dev/")

if __name__ == "__main__":
    main()
