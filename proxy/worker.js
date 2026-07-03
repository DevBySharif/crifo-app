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

// ── Channel health-check config ──────────────────────────────────────
// The master channel list lives on Netlify (editable without an app update).
// A cron trigger tests each stream in rotating batches, records alive/dead in
// KV, and the /channels endpoint serves the cleaned list (dead dropped,
// alive-first). Batch size stays under Cloudflare's 50-subrequest/invocation
// free-plan cap; the cursor rotates so the whole list is re-verified over time.
const CHANNELS_SOURCE = "https://crifo.netlify.app/channels.json";
const HEALTH_BATCH = 45;
const HEALTH_TIMEOUT_MS = 4500;
// A real media-player UA — many IPTV panels 403 an unknown/empty UA.
const STREAM_UA = "VLC/3.0.20 LibVLC/3.0.20";

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

    // ── Route 0: health-checked channel list (/channels) ─────────────
    // Serves the master list with dead streams dropped and alive-first.
    // Cold-start (before the cron has run) falls back to the raw Netlify
    // list so the app is never left without channels.
    if (url.pathname === "/channels" || url.pathname === "/channels.json") {
      try {
        const base = await loadBase(env);
        const status = await loadJson(env, "status", {});
        const cleaned = base
          .filter((c) => {
            const s = status[c.id];
            return !s || s.ok; // keep unknown + alive, drop confirmed-dead
          })
          .map((c, i) => ({ c, i, rank: status[c.id]?.ok ? 0 : 1 }))
          .sort((a, b) => a.rank - b.rank || a.i - b.i) // alive first, stable
          // live: true only for streams confirmed reachable this cycle.
          .map((x) => ({ ...x.c, live: status[x.c.id]?.ok === true }));
        return new Response(
          JSON.stringify({ channels: cleaned, updated: Date.now() }),
          {
            headers: {
              "Content-Type": "application/json",
              "Cache-Control": "public, max-age=120",
              ...cors(),
            },
          }
        );
      } catch (e) {
        return new Response(JSON.stringify({ error: "channels_failed" }), {
          status: 502,
          headers: { "Content-Type": "application/json", ...cors() },
        });
      }
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

  // ── Cron: rotating stream health-check ──────────────────────────────
  // Configured via wrangler.toml [triggers] crons. Each run tests the next
  // HEALTH_BATCH channels, updates their alive/dead status in KV, and advances
  // a cursor that wraps around (re-pulling the Netlify list to pick up edits).
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runHealthCheck(env));
  },
};

// KV helpers (env.CHANNELS binding). All no-ops if KV isn't bound.
async function loadJson(env, key, fallback) {
  if (!env.CHANNELS) return fallback;
  const raw = await env.CHANNELS.get(key);
  return raw ? JSON.parse(raw) : fallback;
}
async function saveJson(env, key, value) {
  if (!env.CHANNELS) return;
  await env.CHANNELS.put(key, JSON.stringify(value));
}

// The master channel array — cached in KV, refreshed from Netlify on wrap.
async function loadBase(env) {
  const cached = await loadJson(env, "base", null);
  if (cached && Array.isArray(cached) && cached.length) return cached;
  return await fetchBaseFromSource(env);
}
async function fetchBaseFromSource(env) {
  const r = await fetch(CHANNELS_SOURCE, {
    headers: { "Cache-Control": "no-cache" },
    cf: { cacheTtl: 0 },
  });
  const j = await r.json();
  const arr = Array.isArray(j) ? j : j.channels;
  const list = Array.isArray(arr) ? arr.filter((c) => c && c.id && c.streamUrl) : [];
  if (list.length) await saveJson(env, "base", list);
  return list;
}

// GET the stream with a short timeout + real UA; we only need to confirm the
// manifest/segment endpoint is reachable, so we cancel the body immediately.
async function testStream(streamUrl) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), HEALTH_TIMEOUT_MS);
  try {
    const res = await fetch(streamUrl, {
      method: "GET",
      redirect: "follow",
      signal: ctrl.signal,
      headers: { "User-Agent": STREAM_UA, Accept: "*/*" },
    });
    clearTimeout(timer);
    try { await res.body?.cancel(); } catch (_) {}
    return { ok: res.status >= 200 && res.status < 400, code: res.status };
  } catch (_) {
    clearTimeout(timer);
    return { ok: false, code: 0 };
  }
}

async function runHealthCheck(env) {
  let cursor = await loadJson(env, "cursor", 0);
  let base;
  if (cursor === 0) {
    // Start of a cycle: re-pull the list so channels.json edits are picked up.
    base = await fetchBaseFromSource(env);
  } else {
    base = await loadBase(env);
  }
  if (!base.length) return;
  if (cursor >= base.length) cursor = 0;

  const batch = base.slice(cursor, cursor + HEALTH_BATCH);
  const results = await Promise.allSettled(batch.map((c) => testStream(c.streamUrl)));

  const status = await loadJson(env, "status", {});
  const now = Date.now();
  batch.forEach((c, i) => {
    const r = results[i];
    const val = r.status === "fulfilled" ? r.value : { ok: false, code: 0 };
    status[c.id] = { ok: val.ok, code: val.code, ts: now };
  });

  let next = cursor + HEALTH_BATCH;
  if (next >= base.length) next = 0; // wrap → next cycle re-pulls source
  await saveJson(env, "status", status);
  await saveJson(env, "cursor", next);
}

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
