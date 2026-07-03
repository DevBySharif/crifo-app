/**
 * CriFO FotMob proxy — Cloudflare Worker
 *
 * Why: FotMob rate-limits/blocks by client IP. On mobile carriers (CGNAT,
 * thousands of users behind one IP) FotMob returns JSON `null` and the app
 * looks empty. Routing requests through this Worker means FotMob sees
 * Cloudflare's IP pool instead of the carrier IP, so data loads everywhere.
 *
 * The app keeps generating the `x-mas` token client-side (it signs the real
 * fotmob.com URL). This Worker just reconstructs that URL from the path and
 * forwards the request with the token + browser-like headers.
 *
 * Deploy (2 min):
 *   1. https://dash.cloudflare.com → Workers & Pages → Create → Worker
 *   2. Paste this file, click Deploy
 *   3. Copy the *.workers.dev URL, put it in _PROXY in fotmob_client.dart
 */

const ORIGIN = "https://www.fotmob.com";

const FORWARD_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "en-US,en;q=0.9",
  "Referer": "https://www.fotmob.com/",
  "Origin": "https://www.fotmob.com",
};

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: cors() });
    }

    // Only proxy the FotMob data API — refuse anything else.
    if (!url.pathname.startsWith("/api/")) {
      return new Response("Not found", { status: 404, headers: cors() });
    }

    const target = ORIGIN + url.pathname + url.search;
    const headers = new Headers(FORWARD_HEADERS);
    const xmas = request.headers.get("x-mas");
    if (xmas) headers.set("x-mas", xmas);

    let upstream;
    try {
      upstream = await fetch(target, { headers, cf: { cacheTtl: 10 } });
    } catch (e) {
      return new Response(JSON.stringify({ error: "upstream_failed" }), {
        status: 502,
        headers: { "Content-Type": "application/json", ...cors() },
      });
    }

    const body = await upstream.text();
    return new Response(body, {
      status: upstream.status,
      headers: {
        "Content-Type":
          upstream.headers.get("Content-Type") || "application/json",
        "Cache-Control": "public, max-age=15",
        ...cors(),
      },
    });
  },
};

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "x-mas, content-type",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
  };
}
