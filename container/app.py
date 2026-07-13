# yt-dlp + ffmpeg audio pipeline — runs inside CF Container.
# HTTP server on port 8080. POST /import {url, title, artist, album?}
# Downloads YouTube audio → Opus encode → streams back to Worker.

import http.server
import json
import os
import subprocess
import sys
import tempfile
import shutil

PORT = int(os.environ.get("PORT", "8080"))


def run(cmd: list[str], timeout: int = 600) -> tuple[int, str, str]:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/import":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        url = data.get("url", "")
        title = data.get("title", "")
        artist = data.get("artist", "")
        album = data.get("album", "")

        if not url:
            self.send_error(400, "Missing url")
            return

        # Step 0: Auto-extract YouTube metadata if not provided
        if not title or not artist:
            print(f"[yt-dlp] Extracting metadata from: {url}", file=sys.stderr)
            rc, out, _ = run(
                ["yt-dlp", "--print", "%(title)s|||%(uploader)s", "--no-playlist", "--no-progress", url],
                timeout=30,
            )
            if rc == 0 and out.strip():
                parts = out.strip().split("|||", 1)
                if not title:
                    title = parts[0].strip()
                if len(parts) > 1 and not artist:
                    artist = parts[1].strip()
                print(f"[yt-dlp] Title: {title}, Artist: {artist}", file=sys.stderr)

        title = title or "YouTube Import"
        artist = artist or "Unknown"

        workdir = tempfile.mkdtemp(prefix="ytdl-")
        try:
            # Step 1: Download audio with yt-dlp
            print(f"[yt-dlp] Downloading: {url}", file=sys.stderr)
            rc, out, err = run(
                [
                    "yt-dlp",
                    "--extract-audio",
                    "--audio-format", "opus",
                    "--audio-quality", "48K",
                    "--output", f"{workdir}/%(title)s.%(ext)s",
                    "--no-playlist",
                    "--no-progress",
                    url,
                ],
                timeout=600,
            )
            if rc != 0:
                self.send_error(500, f"yt-dlp failed: {err[:500]}")
                return

            # Find the output file
            opus_file = None
            for f in os.listdir(workdir):
                if f.endswith(".opus"):
                    opus_file = os.path.join(workdir, f)
                    break

            # If no opus, try to convert whatever we got
            if not opus_file:
                for f in os.listdir(workdir):
                    for ext in (".m4a", ".webm", ".mp3", ".ogg"):
                        if f.endswith(ext):
                            src = os.path.join(workdir, f)
                            dst = os.path.join(workdir, f"{f[: -len(ext)]}.opus")
                            print(f"[ffmpeg] Converting {f} → opus", file=sys.stderr)
                            ffmpeg_cmd = [
                                "ffmpeg", "-i", src,
                                "-c:a", "libopus", "-b:a", "48k", "-vbr", "on",
                                "-metadata", f"title={title}",
                                "-metadata", f"artist={artist}",
                            ]
                            if album:
                                ffmpeg_cmd += ["-metadata", f"album={album}"]
                            ffmpeg_cmd += [dst, "-y"]
                            rc2, _, err2 = run(ffmpeg_cmd, timeout=300)
                            if rc2 == 0:
                                opus_file = dst
                            break
                    if opus_file:
                        break

            if not opus_file:
                self.send_error(500, "No audio file produced")
                return

            size = os.path.getsize(opus_file)
            duration = "0"
            try:
                rc3, dur_out, _ = run(
                    ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
                     "-of", "csv=p=0", opus_file], timeout=10
                )
                if rc3 == 0:
                    duration = dur_out.strip()
            except Exception:
                pass

            print(f"[done] {os.path.basename(opus_file)} size={size} duration={duration}s", file=sys.stderr)

            # Stream the Opus file back to the Worker
            self.send_response(200)
            self.send_header("Content-Type", "audio/ogg; codecs=opus")
            self.send_header("Content-Length", str(size))
            self.send_header("X-Audio-Duration", str(duration))
            self.send_header("X-Audio-Title", title)
            self.send_header("X-Audio-Artist", artist)
            if album:
                self.send_header("X-Audio-Album", album)
            self.end_headers()

            with open(opus_file, "rb") as fh:
                shutil.copyfileobj(fh, self.wfile)

        except Exception as e:
            print(f"[error] {e}", file=sys.stderr)
            try:
                self.send_error(500, str(e))
            except Exception:
                pass
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    def log_message(self, format, *args):
        print(f"[http] {args[0]}", file=sys.stderr)


if __name__ == "__main__":
    print(f"[serve] yt-dlp container listening on :{PORT}", file=sys.stderr)
    httpd = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
    httpd.serve_forever()
