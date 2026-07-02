import { Hono } from 'hono';
import type {
  AppTokenResponse,
  Bindings,
  ChannelEventsResponse,
  ErrorResponse,
  LoginURLResponse,
  PlaybackResponse,
  ReportRequest,
  TokenResponse,
} from './types';
import { PLAYBACK_HASH_KV_KEY, REPORT_KV_PREFIX, REPORT_TTL_SECONDS, VIEWER_SCOPES } from './types';
import {
  buildLoginURL,
  clientCredentials,
  exchangeCode,
  fetchChannelEvents,
  refreshToken,
  resolveClipPlayback,
  resolveLivePlayback,
  resolveVodPlayback,
  TwitchError,
  validateToken,
} from './twitch';
import { isMediaPlaylist, rewriteUris, stripAds } from './hls';
import { privacyPage, termsPage } from './legal';

const APP_TOKEN_KEY = 'app_token';
const APP_TOKEN_SKEW_SECONDS = 60;

const app = new Hono<{ Bindings: Bindings }>();

function fail(status: number, message: string): Response {
  const body: ErrorResponse = { error: message };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function statusFor(err: unknown): number {
  if (err instanceof TwitchError) return err.status >= 400 ? err.status : 502;
  return 502;
}

function messageFor(err: unknown): string {
  if (err instanceof TwitchError) return err.message;
  console.error('unexpected error:', err);
  return 'unexpected error';
}

function isTimeout(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { name?: unknown }).name === 'TimeoutError';
}

const CHANNEL_LOGIN_RE = /^[a-zA-Z0-9_]{1,25}$/;
const VOD_ID_RE = /^\d+$/;
const CLIP_SLUG_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/;

const PROXY_HOST_SUFFIXES = ['ttvnw.net', 'twitch.tv', 'twitchcdn.net', 'cloudfront.net'] as const;

function isAllowedProxyHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return PROXY_HOST_SUFFIXES.some((suffix) => host === suffix || host.endsWith(`.${suffix}`));
}

async function sha256(value: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return new Uint8Array(digest);
}

async function constantTimeEquals(a: string, b: string): Promise<boolean> {
  const [da, db] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < da.length; i++) diff |= (da[i] ?? 0) ^ (db[i] ?? 0);
  return diff === 0;
}

async function toTokenResponse(
  payload: { access_token: string; refresh_token?: string; expires_in: number; scope?: string[] },
): Promise<TokenResponse> {
  const response: TokenResponse = {
    accessToken: payload.access_token,
    expiresIn: payload.expires_in,
  };
  if (payload.refresh_token !== undefined) response.refreshToken = payload.refresh_token;
  if (payload.scope !== undefined) response.scope = payload.scope;
  try {
    const validation = await validateToken(payload.access_token);
    if (validation.user_id !== undefined) response.userID = validation.user_id;
    if (validation.login !== undefined) response.login = validation.login;
    if (response.scope === undefined && validation.scopes !== undefined) {
      response.scope = validation.scopes;
    }
  } catch (err) {
    console.error('token validation enrichment failed:', err);
  }
  return response;
}

app.post('/auth/exchange', async (c) => {
  let body: { code?: string; redirectURI?: string };
  try {
    body = await c.req.json();
  } catch {
    return fail(400, 'invalid JSON body');
  }
  if (!body.code || !body.redirectURI) {
    return fail(400, 'code and redirectURI are required');
  }
  try {
    const payload = await exchangeCode(
      c.env.TWITCH_CLIENT_ID,
      c.env.TWITCH_CLIENT_SECRET,
      body.code,
      body.redirectURI,
    );
    return c.json(await toTokenResponse(payload));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

app.post('/auth/refresh', async (c) => {
  let body: { refreshToken?: string };
  try {
    body = await c.req.json();
  } catch {
    return fail(400, 'invalid JSON body');
  }
  if (!body.refreshToken) {
    return fail(400, 'refreshToken is required');
  }
  try {
    const payload = await refreshToken(
      c.env.TWITCH_CLIENT_ID,
      c.env.TWITCH_CLIENT_SECRET,
      body.refreshToken,
    );
    return c.json(await toTokenResponse(payload));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

app.get('/auth/app-token', async (c) => {
  try {
    const now = Math.floor(Date.now() / 1000);
    const cached = await c.env.TOKENS.get(APP_TOKEN_KEY, 'json');
    if (cached !== null) {
      const value = cached as { accessToken: string; expiresAt: number };
      const remaining = Math.max(60, value.expiresAt - now);
      return c.json({ accessToken: value.accessToken, expiresIn: remaining } satisfies AppTokenResponse);
    }
    const payload = await clientCredentials(c.env.TWITCH_CLIENT_ID, c.env.TWITCH_CLIENT_SECRET);
    const ttl = Math.max(60, payload.expires_in - APP_TOKEN_SKEW_SECONDS);
    await c.env.TOKENS.put(
      APP_TOKEN_KEY,
      JSON.stringify({ accessToken: payload.access_token, expiresAt: now + payload.expires_in }),
      { expirationTtl: ttl },
    );
    return c.json({ accessToken: payload.access_token, expiresIn: payload.expires_in } satisfies AppTokenResponse);
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

app.get('/auth/login-url', (c) => {
  const redirectURI = c.req.query('redirectURI');
  if (!redirectURI) {
    return fail(400, 'redirectURI is required');
  }
  const state = c.req.query('state');
  const url = buildLoginURL(c.env.TWITCH_CLIENT_ID, redirectURI, VIEWER_SCOPES, state);
  const response: LoginURLResponse = { url };
  return c.json(response);
});

const APP_CALLBACK_SCHEME = 'embr://auth/callback';

app.get('/auth/callback', (c) => {
  const incoming = new URL(c.req.url);
  const target = new URL(APP_CALLBACK_SCHEME);
  incoming.searchParams.forEach((value, key) => target.searchParams.set(key, value));
  return new Response(null, { status: 302, headers: { Location: target.toString() } });
});

function proxyURLFor(c: { req: { url: string } }): { proxyBase: string } {
  const here = new URL(c.req.url);
  return { proxyBase: `${here.origin}/hls/proxy` };
}

/// Confirms the usher master is reachable before handing the app a URL.
/// Offline/ended/sub-gated channels still mint a token but 404 at usher, so this
/// surfaces a real 404 the app renders as "Channel Offline" instead of a retry loop.
/// Extracts the PlaybackAccessToken expiry (epoch seconds) embedded in the usher
/// URL's `token` param, so the app can proactively re-resolve before it lapses.
function expiresFromUsher(usher: string): number | undefined {
  try {
    const raw = new URL(usher).searchParams.get('token');
    if (!raw) return undefined;
    const parsed = JSON.parse(raw) as { expires?: number };
    return typeof parsed.expires === 'number' ? parsed.expires : undefined;
  } catch {
    return undefined;
  }
}

/// Fetches an upstream URL with a timeout, converting a timeout into a 504
/// TwitchError so route-level catch blocks render it uniformly.
async function fetchUpstream(url: string, timeoutMs: number, label: string): Promise<Response> {
  try {
    return await fetch(url, { headers: { Accept: '*/*' }, signal: AbortSignal.timeout(timeoutMs) });
  } catch (err) {
    if (isTimeout(err)) {
      console.error(`${label} timed out`);
      throw new TwitchError('upstream timeout', 504);
    }
    throw err;
  }
}

async function playbackResponse(c: { req: { url: string } }, usher: string): Promise<Response> {
  const check = await fetchUpstream(usher, 5000, 'usher preflight');
  await check.body?.cancel();
  if (!check.ok) {
    return fail(check.status === 404 ? 404 : 502, `stream unavailable (${check.status})`);
  }
  const { proxyBase } = proxyURLFor(c);
  const response: PlaybackResponse = { url: `${proxyBase}?src=${encodeURIComponent(usher)}` };
  const expiresAt = expiresFromUsher(usher);
  if (expiresAt !== undefined) response.expiresAt = expiresAt;
  return new Response(JSON.stringify(response), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function playbackHashOverride(c: { env: Bindings }): Promise<string | undefined> {
  try {
    const value = await c.env.TOKENS.get(PLAYBACK_HASH_KV_KEY);
    return value && value.length > 0 ? value : undefined;
  } catch (err) {
    console.error('playback hash override lookup failed:', err);
    return undefined;
  }
}

app.get('/playback/vod/:id', async (c) => {
  const id = c.req.param('id');
  if (!VOD_ID_RE.test(id)) return fail(400, 'invalid vod id');
  try {
    const hash = await playbackHashOverride(c);
    return await playbackResponse(c, await resolveVodPlayback(id, hash));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

app.get('/playback/clip/:slug', async (c) => {
  const slug = c.req.param('slug');
  if (!CLIP_SLUG_RE.test(slug)) return fail(400, 'invalid clip slug');
  try {
    return c.json(await resolveClipPlayback(slug));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

/// Serves a minimal page that embeds the official Twitch player with this worker's
/// own host as `parent`, so `WebViewPlayer` has a working compliant fallback when
/// the ad-stripped HLS path fails. Anonymous playback (shows ads) is the trade-off.
app.get('/embed', (c) => {
  const channel = c.req.query('channel');
  if (!channel) return fail(400, 'channel is required');
  if (!CHANNEL_LOGIN_RE.test(channel)) return fail(400, 'invalid channel');
  const host = new URL(c.req.url).hostname;
  const safeChannel = encodeURIComponent(channel);
  const safeParent = encodeURIComponent(host);
  const muted = c.req.query('muted') === 'true' ? 'true' : 'false';
  const html = `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">` +
    `<style>html,body{margin:0;background:#000;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%}</style></head>` +
    `<body><iframe src="https://player.twitch.tv/?channel=${safeChannel}&parent=${safeParent}&autoplay=true&muted=${muted}&playsinline=true" ` +
    `allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>`;
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
});

app.get('/events/:login', async (c) => {
  const login = c.req.param('login');
  if (!CHANNEL_LOGIN_RE.test(login)) return fail(400, 'invalid channel login');
  let events: ChannelEventsResponse = { poll: null, prediction: null };
  try {
    events = await fetchChannelEvents(login);
  } catch (err) {
    console.error('channel events lookup failed:', err);
  }
  return new Response(JSON.stringify(events), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});

app.get('/playback/:login', async (c) => {
  const login = c.req.param('login');
  if (!CHANNEL_LOGIN_RE.test(login)) return fail(400, 'invalid channel login');
  try {
    const hash = await playbackHashOverride(c);
    return await playbackResponse(c, await resolveLivePlayback(login, hash));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

const PLAYLIST_CONTENT_TYPE = 'application/vnd.apple.mpegurl';

app.get('/hls/proxy', async (c) => {
  const src = c.req.query('src');
  if (!src) {
    return fail(400, 'src is required');
  }
  let target: URL;
  try {
    target = new URL(src);
  } catch {
    return fail(400, 'src must be an absolute URL');
  }
  if (target.protocol !== 'https:' || !isAllowedProxyHost(target.hostname)) {
    console.error(`hls proxy rejected host: ${target.hostname}`);
    return fail(403, 'src host not allowed');
  }
  try {
    const upstream = await fetchUpstream(target.toString(), 8000, 'hls proxy upstream');
    if (!upstream.ok) {
      return fail(upstream.status, `upstream responded ${upstream.status}`);
    }
    const text = await upstream.text();
    const { proxyBase } = proxyURLFor(c);

    let playlist: string;
    if (isMediaPlaylist(text)) {
      const stripped = stripAds(text);
      const safe = stripped.includes('#EXTINF') ? stripped : text;
      playlist = rewriteUris(safe, target.toString(), null);
    } else {
      playlist = rewriteUris(text, target.toString(), proxyBase);
    }

    return new Response(playlist, {
      status: 200,
      headers: {
        'Content-Type': PLAYLIST_CONTENT_TYPE,
        'Cache-Control': 'no-store',
      },
    });
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
});

const REPORT_MAX_BODY_BYTES = 8 * 1024;
const REPORT_RATE_LIMIT_MAX = 5;
const REPORT_RATE_LIMIT_WINDOW_SECONDS = 600;
const REPORT_RATE_KV_PREFIX = 'ratelimit:report:';

/// KV-backed best-effort limiter; eventual consistency means brief overshoot is
/// possible, which is acceptable for abuse throttling here. The counter write is
/// scheduled through `waitUntil` so it never delays the response.
async function reportRateLimited(
  env: Bindings,
  ip: string,
  waitUntil: (promise: Promise<unknown>) => void,
): Promise<boolean> {
  const key = `${REPORT_RATE_KV_PREFIX}${ip}`;
  try {
    const raw = await env.TOKENS.get(key, 'json');
    const now = Math.floor(Date.now() / 1000);
    const state = (raw ?? { count: 0, windowStart: now }) as { count: number; windowStart: number };
    if (now - state.windowStart >= REPORT_RATE_LIMIT_WINDOW_SECONDS) {
      state.count = 0;
      state.windowStart = now;
    }
    if (state.count >= REPORT_RATE_LIMIT_MAX) return true;
    state.count += 1;
    waitUntil(
      env.TOKENS
        .put(key, JSON.stringify(state), { expirationTtl: REPORT_RATE_LIMIT_WINDOW_SECONDS })
        .catch((err) => console.error('report rate limit persist failed:', err)),
    );
    return false;
  } catch (err) {
    console.error('report rate limit check failed:', err);
    return false;
  }
}

/// Receives a user's chat-message report (App Store Guideline 1.2) and stores it for
/// the developer to review. Best-effort: a storage failure still returns 204 so the
/// reporter's flow never breaks.
app.post('/report', async (c) => {
  const declared = Number(c.req.header('Content-Length'));
  if (Number.isFinite(declared) && declared > REPORT_MAX_BODY_BYTES) {
    return fail(413, 'request body too large');
  }
  const raw = await c.req.text();
  if (new TextEncoder().encode(raw).length > REPORT_MAX_BODY_BYTES) {
    return fail(413, 'request body too large');
  }
  let body: ReportRequest;
  try {
    body = JSON.parse(raw) as ReportRequest;
  } catch {
    return fail(400, 'invalid JSON body');
  }
  const waitUntil = (promise: Promise<unknown>): void => c.executionCtx.waitUntil(promise);
  const ip = c.req.header('CF-Connecting-IP') ?? 'unknown';
  const limited = await reportRateLimited(c.env, ip, waitUntil);
  if (limited) {
    return fail(429, 'too many reports, try again later');
  }
  if (!body.reason || (!body.messageID && !body.authorID)) {
    return fail(400, 'reason and a target (messageID or authorID) are required');
  }
  const cap = (value: unknown, max: number): string | undefined =>
    typeof value === 'string' ? value.slice(0, max) : undefined;
  const now = Math.floor(Date.now() / 1000);
  const key = `${REPORT_KV_PREFIX}${now}-${crypto.randomUUID()}`;
  const reason = cap(body.reason, 80);
  const record = {
    kind: reason && /^blocked/i.test(reason) ? 'block' : 'report',
    channel: cap(body.channel, 60),
    messageID: cap(body.messageID, 80),
    authorID: cap(body.authorID, 40),
    authorLogin: cap(body.authorLogin, 60),
    reason,
    text: cap(body.text, 2000),
    at: now,
  };
  waitUntil(
    c.env.TOKENS
      .put(key, JSON.stringify(record), { expirationTtl: REPORT_TTL_SECONDS })
      .catch((err) => console.error('report storage failed:', err)),
  );
  return new Response(null, { status: 204 });
});

/// Authenticated review endpoint (App Store Guideline 1.2 — the developer must act on
/// reports within 24 hours). Lists the stored reports/blocks newest-first. Disabled unless
/// REPORTS_ADMIN_TOKEN is configured; requires `Authorization: Bearer <token>`.
app.get('/reports', async (c) => {
  const token = c.env.REPORTS_ADMIN_TOKEN;
  if (!token) return fail(404, 'not found');
  const header = c.req.header('Authorization') ?? '';
  const authorized = await constantTimeEquals(header, `Bearer ${token}`);
  if (!authorized) return fail(401, 'unauthorized');
  // Keys sort lexicographically == chronologically ascending, so a single 1000-key page
  // would return the OLDEST reports and drop the newest — page through the cursor so the
  // full set is available and the newest-first sort below is meaningful.
  const keys: string[] = [];
  let cursor: string | undefined;
  do {
    const page = await c.env.TOKENS.list({ prefix: REPORT_KV_PREFIX, limit: 1000, cursor });
    for (const entry of page.keys) keys.push(entry.name);
    cursor = page.list_complete ? undefined : (page as { cursor?: string }).cursor;
  } while (cursor);
  const reports: unknown[] = [];
  for (const name of keys) {
    const raw = await c.env.TOKENS.get(name);
    if (raw === null) continue;
    try {
      reports.push(JSON.parse(raw));
    } catch {
      // Skip a corrupt record rather than failing the whole review list.
    }
  }
  reports.sort((a, b) => {
    const at = (r: unknown) => (typeof r === 'object' && r !== null && 'at' in r ? Number((r as { at: unknown }).at) || 0 : 0);
    return at(b) - at(a);
  });
  return c.json({ count: reports.length, reports });
});

app.get('/legal/terms', () => termsPage());
app.get('/legal/privacy', () => privacyPage());

app.onError((err, _c) => fail(statusFor(err), messageFor(err)));

app.notFound(() => fail(404, 'not found'));

export default app;
