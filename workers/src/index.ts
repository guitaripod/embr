import { Hono } from 'hono';
import type {
  AppTokenResponse,
  Bindings,
  ChannelEventsResponse,
  ErrorResponse,
  LoginURLResponse,
  PlaybackResponse,
  TokenResponse,
} from './types';
import { VIEWER_SCOPES } from './types';
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

app.get('/playback/vod/:id', async (c) => {
  try {
    return await playbackResponse(c, await resolveVodPlayback(c.req.param('id')));
  } catch (err) {
    return fail(statusFor(err), messageFor(err));
  }
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
    return await playbackResponse(c, await resolveLivePlayback(c.req.param('login')));
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

app.onError((err, _c) => fail(statusFor(err), messageFor(err)));

app.notFound(() => fail(404, 'not found'));

export default app;
