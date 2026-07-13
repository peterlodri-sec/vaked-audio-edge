// vaked-audio-edge — Opus streaming via Cloudflare Workers + R2
//
// Features:
//   • Range requests with suffix/multi-range support
//   • CORS for cross-origin <audio> embeds
//   • ABR-lite: bitrate selection via clientTcpRtt
//   • Conditional GET (ETag/If-None-Match)
//   • /tracks — JSON catalog of available tracks
//   • /import — YouTube → Opus → R2 via CF Container
//   • Zero Worker heap pressure — R2 body streamed directly

import { Container, getContainer } from "@cloudflare/containers";

export class YTDLContainer extends Container {
  defaultPort = 8080;
  sleepAfter = "5m";
}

export interface Env {
  AUDIO_BUCKET: R2Bucket;
  YTDL_CONTAINER: YTDLContainer;
}

// ---------------------------------------------------------------------------
// Track catalog — single source of truth for metadata.
// R2 keys must be ASCII slugs. Full Unicode in metadata here.
// ---------------------------------------------------------------------------

interface Track {
  key: string; // R2 object key (ASCII slug)
  title: string;
  artist: string;
  album?: string;
  duration: number; // seconds
  bitrate_high: number; // bps — served to fast connections
  bitrate_low: number; // bps — served to slow connections
}

const TRACKS: Record<string, Track> = {
  "rufus-du-sol-mayan-warrior-burning-man-2024": {
    key: "music/rufus-du-sol-mayan-warrior-burning-man-2024.opus",
    title: "RÜFÜS DU SOL (DJ SET) — Mayan Warrior — Burning Man 2024",
    artist: "RÜFÜS DU SOL",
    album: "Burning Man 2024",
    duration: 6318,
    bitrate_high: 48000,
    bitrate_low: 32000,
  },
};

// ---------------------------------------------------------------------------
// ABR-lite: pick variant based on client round-trip time
// ---------------------------------------------------------------------------

const RTT_FAST = 50; // ms — below this, serve high bitrate
const RTT_OK = 200; // ms — below this, serve medium / default

function pickBitrate(track: Track, rttMs: number | undefined): number {
  if (rttMs === undefined) return track.bitrate_high;
  return rttMs < RTT_FAST ? track.bitrate_high : track.bitrate_low;
}

function pickKey(track: Track, bitrate: number): string {
  if (bitrate === track.bitrate_high) return track.key;
  // Low-bitrate variant: insert _lo before extension
  return track.key.replace(/\.opus$/, "_lo.opus");
}

// ---------------------------------------------------------------------------
// Range header parser — handles bytes=0-1023, bytes=500-, bytes=-500
// ---------------------------------------------------------------------------

interface ParsedRange {
  offset: number;
  length?: number; // undefined = to end of file
}

function parseRange(header: string, fileSize: number): ParsedRange | null {
  const match = header.match(/bytes=(\d*)-(\d*)/);
  if (!match) return null;

  const start = match[1] ? parseInt(match[1], 10) : 0;
  const end = match[2] ? parseInt(match[2], 10) : fileSize - 1;

  if (match[1] === "" && match[2] !== "") {
    // Suffix range: bytes=-N means last N bytes
    const suffix = parseInt(match[2], 10);
    return { offset: Math.max(0, fileSize - suffix), length: suffix };
  }

  const offset = Math.min(start, fileSize - 1);
  const length = end >= offset ? end - offset + 1 : fileSize - offset;
  return { offset, length };
}

// ---------------------------------------------------------------------------
// CORS headers — always set, single source
// ---------------------------------------------------------------------------

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "Range, If-None-Match",
    "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges, Content-Length, ETag",
    "Access-Control-Max-Age": "86400",
  };
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin);

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    // ------------------------------------------------------------------
    // /tracks — JSON catalog
    // ------------------------------------------------------------------
    if (url.pathname === "/tracks") {
      const catalog = Object.entries(TRACKS).map(([slug, t]) => ({
        slug,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        urls: {
          high: `/stream/${slug}`,
          low: `/stream/${slug}?abr=low`,
        },
      }));
      return new Response(JSON.stringify(catalog, null, 2), {
        headers: { "Content-Type": "application/json", ...cors },
      });
    }

    // ------------------------------------------------------------------
    // /import — YouTube → Opus → R2 via CF Container
    // ------------------------------------------------------------------
    if (url.pathname === "/import" && request.method === "POST") {
      if (!env.YTDL_CONTAINER) {
        return new Response(
          JSON.stringify({ error: "Container binding not configured. Deploy with --container flag." }),
          { status: 501, headers: { "Content-Type": "application/json", ...cors } }
        );
      }

      let body: { url?: string; title?: string; artist?: string; album?: string; slug?: string };
      try {
        body = await request.json();
      } catch {
        return new Response(
          JSON.stringify({ error: "Invalid JSON body" }),
          { status: 400, headers: { "Content-Type": "application/json", ...cors } }
        );
      }

      if (!body.url) {
        return new Response(
          JSON.stringify({ error: "Missing url field" }),
          { status: 400, headers: { "Content-Type": "application/json", ...cors } }
        );
      }

      // Tentative slug — will be refined after container returns metadata
      const tentativeSlug = body.slug || `import-${Date.now()}`;

      console.log(`[import] Starting: ${body.url}`);

      try {
        // Spawn container — downloads on CF network, encodes, returns Opus stream
        const container = getContainer(env.YTDL_CONTAINER, tentativeSlug);
        const containerResp = await container.fetch("http://container/import", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            url: body.url,
            title: body.title || "",
            artist: body.artist || "",
            album: body.album || "",
          }),
        });

        if (!containerResp.ok) {
          const err = await containerResp.text();
          console.error(`[import] Container failed: ${containerResp.status} ${err}`);
          return new Response(
            JSON.stringify({ error: `Container failed: ${err}` }),
            { status: 502, headers: { "Content-Type": "application/json", ...cors } }
          );
        }

        const opusBody = containerResp.body;
        if (!opusBody) {
          return new Response(
            JSON.stringify({ error: "Container returned empty body" }),
            { status: 502, headers: { "Content-Type": "application/json", ...cors } }
          );
        }

        const duration = parseFloat(containerResp.headers.get("X-Audio-Duration") || "0");
        const detectedTitle = containerResp.headers.get("X-Audio-Title") || "";
        const detectedArtist = containerResp.headers.get("X-Audio-Artist") || "";

        // Slug from detected title, or user-provided, or fallback
        const slug = body.slug
          || (detectedTitle || body.title || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
          || tentativeSlug;
        const r2Key = `music/${slug}.opus`;

        await env.AUDIO_BUCKET.put(r2Key, opusBody, {
          httpMetadata: {
            contentType: "audio/ogg; codecs=opus",
            cacheControl: "public, max-age=31536000, immutable",
          },
        });

        console.log(`[import] Done: ${r2Key} (${Math.round(duration)}s)`);

        return new Response(
          JSON.stringify({
            ok: true,
            slug,
            key: r2Key,
            title: detectedTitle || body.title || slug,
            artist: detectedArtist || body.artist || "",
            duration: Math.round(duration),
            streamUrl: `/stream/${slug}`,
          }),
          { headers: { "Content-Type": "application/json", ...cors } }
        );
      } catch (e: any) {
        console.error(`[import] Error: ${e.message || e}`);
        return new Response(
          JSON.stringify({ error: `Import failed: ${e.message || e}` }),
          { status: 500, headers: { "Content-Type": "application/json", ...cors } }
        );
      }
    }

    // ------------------------------------------------------------------
    // /stream/:slug — stream audio
    // ------------------------------------------------------------------
    if (url.pathname.startsWith("/stream/")) {
      const slug = url.pathname.replace("/stream/", "").split("/")[0];
      const track = TRACKS[slug];
      if (!track) {
        return new Response("Track not found", { status: 404, headers: cors });
      }

      // ABR: read client RTT from CF headers
      const rttHeader = request.headers.get("cf-client-tcp-rtt") || request.cf?.clientTcpRtt;
      const rttMs = rttHeader ? parseInt(String(rttHeader), 10) : undefined;
      const forceLow = url.searchParams.get("abr") === "low";
      const bitrate = forceLow ? track.bitrate_low : pickBitrate(track, rttMs);
      const key = pickKey(track, bitrate);

      // Fetch metadata from R2
      const object = await env.AUDIO_BUCKET.head(key);
      if (!object) {
        return new Response("Audio file not found in R2", { status: 404, headers: cors });
      }

      const fileSize = object.size;
      const etag = object.httpEtag || object.etag || "";

      // Conditional GET — 304 if client already has this version
      const ifNoneMatch = request.headers.get("If-None-Match");
      if (ifNoneMatch && etag && ifNoneMatch === etag) {
        return new Response(null, { status: 304, headers: { ...cors, ETag: etag } });
      }

      // Range request
      const rangeHeader = request.headers.get("Range");
      let r2Options: R2GetOptions = {};

      if (rangeHeader) {
        const parsed = parseRange(rangeHeader, fileSize);
        if (parsed) {
          r2Options.range = { offset: parsed.offset, length: parsed.length };
        }
      }

      // Pull from R2 — body is a ReadableStream, no buffering
      const audioObject = await env.AUDIO_BUCKET.get(key, r2Options);
      if (!audioObject || !audioObject.body) {
        return new Response("Failed to fetch audio", { status: 500, headers: cors });
      }

      // Build response headers
      const headers = new Headers({
        "Content-Type": "audio/ogg; codecs=opus",
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=31536000, immutable",
        ...cors,
      });

      if (etag) headers.set("ETag", etag);

      if (rangeHeader && audioObject.range) {
        const rangeStart = audioObject.range.offset ?? r2Options.range?.offset ?? 0;
        const rangeLen = audioObject.range.length ?? (fileSize - rangeStart);
        headers.set("Content-Range", `bytes ${rangeStart}-${rangeStart + rangeLen - 1}/${fileSize}`);
        headers.set("Content-Length", String(rangeLen));
        return new Response(audioObject.body, { status: 206, headers });
      }

      headers.set("Content-Length", String(fileSize));
      return new Response(audioObject.body, { status: 200, headers });
    }

    // ------------------------------------------------------------------
    // / — HTML player
    // ------------------------------------------------------------------
    if (url.pathname === "/" || url.pathname === "") {
      const playerHTML = generatePlayerHTML();
      return new Response(playerHTML, {
        headers: { "Content-Type": "text/html; charset=utf-8", ...cors },
      });
    }

    return new Response("Not found", { status: 404, headers: cors });
  },
};

// ---------------------------------------------------------------------------
// Inline HTML player — no build step, no deps.
// ---------------------------------------------------------------------------

function generatePlayerHTML(): string {
  const tracksJSON = JSON.stringify(
    Object.entries(TRACKS).map(([slug, t]) => ({
      slug,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
      src: `/stream/${slug}`,
    }))
  );

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>vaked audio</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a0f;
    color: #e0e8f0;
    font-family: 'JetBrains Mono', monospace;
    min-height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
  }
  .player {
    width: 100%;
    max-width: 480px;
    padding: 2rem;
  }
  h1 { font-size: 1rem; color: #00d4ff; margin-bottom: 2rem; }
  .track {
    padding: 1rem;
    margin-bottom: 0.5rem;
    border: 1px solid #1a1b26;
    border-radius: 4px;
    cursor: pointer;
    transition: border-color 0.2s, background 0.2s;
  }
  .track:hover, .track.active {
    border-color: #ff00ff;
    background: #1a1b2644;
  }
  .track-title { font-size: 0.9rem; color: #e0e8f0; }
  .track-meta  { font-size: 0.75rem; color: #c0caf5; margin-top: 0.25rem; }
  .track-duration { color: #00ff9c; }
  .status { font-size: 0.75rem; color: #ff0055; margin-top: 1rem; }
  .status.playing { color: #00ff9c; }
  audio { display: none; }
</style>
</head>
<body>
<div class="player">
  <h1>vaked audio</h1>
  <div id="tracks"></div>
  <div id="status" class="status"></div>
  <audio id="audio" preload="none"></audio>
</div>
<script>
  const tracks = ${tracksJSON};
  const audio = document.getElementById('audio');
  const status = document.getElementById('status');
  const container = document.getElementById('tracks');
  let current = null;

  function fmtDuration(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  tracks.forEach(track => {
    const el = document.createElement('div');
    el.className = 'track';
    el.innerHTML = '<div class="track-title">' + track.title + '</div>' +
      '<div class="track-meta">' +
        track.artist +
        (track.album ? ' · ' + track.album : '') +
        ' · <span class="track-duration">' + fmtDuration(track.duration) + '</span>' +
      '</div>';
    el.onclick = () => play(track, el);
    container.appendChild(el);
  });

  function play(track, el) {
    if (current) current.classList.remove('active');
    el.classList.add('active');
    current = el;
    audio.src = track.src;
    audio.play().catch(() => {});
    status.textContent = track.title;
    status.className = 'status playing';
    audio.onended = () => {
      status.textContent = '';
      status.className = 'status';
      el.classList.remove('active');
      current = null;
    };
  }
</script>
</body>
</html>`;
}
