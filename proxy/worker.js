/**
 * CriFO FotMob + football-data.org proxy — Cloudflare Worker
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
 * football-data.org: The API token is stored as a Cloudflare Worker secret
 * (never in APK source) and injected server-side here.
 * To set the secret: wrangler secret put FD_TOKEN
 *
 * Routes:
 *   /api/*   → https://www.fotmob.com/api/*
 *   /fd/*    → https://api.football-data.org/v4/*  (token injected here)
 *
 * Deploy (2 min):
 *   1. https://dash.cloudflare.com → Workers & Pages → Create → Worker
 *   2. Paste this file, click Deploy
 *   3. wrangler secret put FD_TOKEN  (paste your football-data.org token)
 *   4. Copy the *.workers.dev URL, put it in _PROXY in fotmob_client.dart
 */

const FOTMOB_ORIGIN = "https://www.fotmob.com";
const FD_ORIGIN     = "https://api.football-data.org/v4";
const IMG_ORIGIN    = "https://images.fotmob.com";
const ESPN_ORIGIN   = "https://site.api.espn.com";
const ESPNW_ORIGIN  = "https://site.web.api.espn.com";
const SDB_ORIGIN    = "https://www.thesportsdb.com";

const FOTMOB_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "en-US,en;q=0.9",
  "Referer": "https://www.fotmob.com/",
  "Origin": "https://www.fotmob.com",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: cors() });
    }

    // ── Route 1: FotMob data API (/api/*) ─────────────────────────────
    if (url.pathname.startsWith("/api/")) {
      const target = FOTMOB_ORIGIN + url.pathname + url.search;
      const headers = new Headers(FOTMOB_HEADERS);
      // Sign server-side so the signing key never ships in the app.
      // Falls back to a client-provided token if present (legacy apps).
      const xmas = request.headers.get("x-mas") || await signXMas(target, env);
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
    }

    // ── Route 2: football-data.org (/fd/*) ────────────────────────────
    // Token is stored as a Cloudflare secret (env.FD_TOKEN), never in APK.
    if (url.pathname.startsWith("/fd/")) {
      // Strip /fd prefix to get /competitions/...
      const fdPath = url.pathname.replace(/^\/fd/, "");
      const target = FD_ORIGIN + fdPath + url.search;

      const token = env.FD_TOKEN ?? "";
      if (!token) {
        return new Response(JSON.stringify({ error: "fd_token_not_configured" }), {
          status: 503,
          headers: { "Content-Type": "application/json", ...cors() },
        });
      }

      let upstream;
      try {
        upstream = await fetch(target, {
          headers: {
            "X-Auth-Token": token,
            "Accept": "application/json",
          },
          cf: { cacheTtl: 300 }, // standings rarely change — cache 5 min
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: "fd_upstream_failed" }), {
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
          "Cache-Control": "public, max-age=60",
          ...cors(),
        },
      });
    }

    // ── Route 3: images (/img/*) → images.fotmob.com ─────────────────
    // Binary passthrough (logos, player photos). Long cache.
    if (url.pathname.startsWith("/img/")) {
      const target = IMG_ORIGIN + url.pathname.replace(/^\/img/, "") + url.search;
      try {
        const up = await fetch(target, { cf: { cacheTtl: 86400 } });
        return new Response(up.body, {
          status: up.status,
          headers: {
            "Content-Type": up.headers.get("Content-Type") || "image/png",
            "Cache-Control": "public, max-age=86400",
            ...cors(),
          },
        });
      } catch (e) {
        return new Response(null, { status: 502, headers: cors() });
      }
    }

    // ── Route 4: ESPN + TheSportsDB (fallback data source) ────────────
    // /espn/*  → site.api.espn.com   /espnw/* → site.web.api.espn.com
    // /sdb/*   → thesportsdb.com
    const espnMap = [
      ["/espnw/", ESPNW_ORIGIN],
      ["/espn/", ESPN_ORIGIN],
      ["/sdb/", SDB_ORIGIN],
    ];
    for (const [prefix, origin] of espnMap) {
      if (url.pathname.startsWith(prefix)) {
        // Strip the prefix but keep the leading slash of the real path.
        const rest = url.pathname.slice(prefix.length - 1);
        const finalTarget = origin + rest + url.search;
        try {
          const up = await fetch(finalTarget, {
            headers: { "Accept": "application/json, */*", "User-Agent": FOTMOB_HEADERS["User-Agent"] },
            cf: { cacheTtl: 15 },
          });
          const body = await up.text();
          return new Response(body, {
            status: up.status,
            headers: {
              "Content-Type": up.headers.get("Content-Type") || "application/json",
              "Cache-Control": "public, max-age=15",
              ...cors(),
            },
          });
        } catch (e) {
          return new Response(JSON.stringify({ error: "espn_upstream_failed" }), {
            status: 502, headers: { "Content-Type": "application/json", ...cors() },
          });
        }
      }
    }

    // Anything else — refuse.
    return new Response("Not found", { status: 404, headers: cors() });
  },
};

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "x-mas, content-type",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
  };
}

// ── FotMob x-mas token, generated server-side ────────────────────────
// sha256( jsonEncode(body) + KEY ), then base64( jsonEncode({body,signature}) ).
// KEY + FOO are Cloudflare secrets (env.FOTMOB_KEY / env.FOTMOB_FOO) — never in
// this repo or the app. Set them with:  wrangler secret put FOTMOB_KEY
async function signXMas(fullUrl, env) {
  try {
    const key = env.FOTMOB_KEY ?? "";
    const foo = env.FOTMOB_FOO ?? "";
    if (!key) return "";
    const body = { url: fullUrl, code: Date.now(), foo };
    const toSign = JSON.stringify(body) + key;
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(toSign));
    const signature = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
    const payload = JSON.stringify({ body, signature });
    // base64 of a UTF-8 string
    return btoa(unescape(encodeURIComponent(payload)));
  } catch (e) {
    return "";
  }
}
