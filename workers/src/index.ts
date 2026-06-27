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
  return err instanceof Error ? err.message : 'unexpected error';
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
  } catch {
    // validation is best-effort enrichment; the token itself is already valid.
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

async function playbackResponse(c: { req: { url: string } }, usher: string): Promise<Response> {
  const check = await fetch(usher, { headers: { Accept: '*/*' } });
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
  } catch {
    return undefined;
  }
}

app.get('/playback/vod/:id', async (c) => {
  try {
    const hash = await playbackHashOverride(c);
    return await playbackResponse(c, await resolveVodPlayback(c.req.param('id'), hash));
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
  let events: ChannelEventsResponse = { poll: null, prediction: null };
  try {
    events = await fetchChannelEvents(c.req.param('login'));
  } catch {
    // Best-effort: a failed poll/prediction lookup is "no active events", not an error.
  }
  return new Response(JSON.stringify(events), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});

app.get('/playback/:login', async (c) => {
  try {
    const hash = await playbackHashOverride(c);
    return await playbackResponse(c, await resolveLivePlayback(c.req.param('login'), hash));
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
  try {
    const upstream = await fetch(target.toString(), {
      headers: { 'Accept': '*/*' },
    });
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

/// Receives a user's chat-message report (App Store Guideline 1.2) and stores it for
/// the developer to review. Best-effort: a storage failure still returns 204 so the
/// reporter's flow never breaks.
app.post('/report', async (c) => {
  let body: ReportRequest;
  try {
    body = await c.req.json();
  } catch {
    return fail(400, 'invalid JSON body');
  }
  if (!body.reason || (!body.messageID && !body.authorID)) {
    return fail(400, 'reason and a target (messageID or authorID) are required');
  }
  const cap = (value: unknown, max: number): string | undefined =>
    typeof value === 'string' ? value.slice(0, max) : undefined;
  try {
    const now = Math.floor(Date.now() / 1000);
    const key = `${REPORT_KV_PREFIX}${now}-${crypto.randomUUID()}`;
    const record = {
      channel: cap(body.channel, 60),
      messageID: cap(body.messageID, 80),
      authorID: cap(body.authorID, 40),
      authorLogin: cap(body.authorLogin, 60),
      reason: cap(body.reason, 80),
      text: cap(body.text, 2000),
      at: now,
    };
    await c.env.TOKENS.put(key, JSON.stringify(record), { expirationTtl: REPORT_TTL_SECONDS });
  } catch {
    // Storing the report is best-effort; never block the reporter on it.
  }
  return new Response(null, { status: 204 });
});

app.get('/legal/terms', () => termsPage());
app.get('/legal/privacy', () => privacyPage());

app.onError((err, _c) => fail(statusFor(err), messageFor(err)));

app.notFound(() => fail(404, 'not found'));

export default app;
