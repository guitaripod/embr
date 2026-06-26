import { Hono } from 'hono';
import type {
  AppTokenResponse,
  Bindings,
  ErrorResponse,
  LoginURLResponse,
  ReportRequest,
  TokenResponse,
} from './types';
import { REPORT_KV_PREFIX, REPORT_TTL_SECONDS, VIEWER_SCOPES } from './types';
import {
  buildLoginURL,
  clientCredentials,
  exchangeCode,
  refreshToken,
  TwitchError,
  validateToken,
} from './twitch';
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

function htmlResponse(body: string): Response {
  return new Response(body, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

const EMBED_HEAD =
  `<!doctype html><html><head><meta charset="utf-8">` +
  `<meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">` +
  `<style>html,body{margin:0;background:#000;height:100%;overflow:hidden}` +
  `#player,iframe{border:0;width:100%;height:100%}</style></head>`;

const SAFE_HOST = /^[a-z0-9.-]+$/;
const CHANNEL_RE = /^[a-zA-Z0-9_]{1,40}$/;
const VIDEO_RE = /^[0-9]{1,20}$/;
const CLIP_RE = /^[a-zA-Z0-9-]{1,200}$/;

/// Encodes a value as a JS string literal that cannot break out of a `<script>` block,
/// neutralizing `</script>` even though the inputs are already charset-validated.
function jsString(value: string): string {
  return JSON.stringify(value).replace(/</g, '\\u003c').replace(/>/g, '\\u003e');
}

/// Renders the official Twitch Interactive Embed (embed.twitch.tv) for a live channel
/// or a VOD. The embed runs Twitch's own player — including any advertising Twitch
/// serves — and posts player state back to the native app so the overlay can reflect
/// loading / playing / paused / ended / offline. `layout: "video"` hides Twitch's
/// built-in chat because the app renders its own.
function interactiveEmbed(target: string, parent: string, muted: boolean): string {
  return (
    EMBED_HEAD +
    `<body><div id="player"></div>` +
    `<script src="https://embed.twitch.tv/embed/v1.js"></script>` +
    `<script>` +
    `function post(s){try{window.webkit.messageHandlers.embrPlayer.postMessage(s);}catch(e){}}` +
    `var player=null;` +
    `var embed=new Twitch.Embed("player",{width:"100%",height:"100%",${target},` +
    `parent:[${jsString(parent)}],layout:"video",autoplay:true,muted:${muted ? 'true' : 'false'}});` +
    `embed.addEventListener(Twitch.Embed.VIDEO_READY,function(){` +
    `player=embed.getPlayer();post("ready");` +
    `player.addEventListener(Twitch.Player.PLAY,function(){post("playing");});` +
    `player.addEventListener(Twitch.Player.PAUSE,function(){post("paused");});` +
    `player.addEventListener(Twitch.Player.ENDED,function(){post("ended");});` +
    `player.addEventListener(Twitch.Player.OFFLINE,function(){post("offline");});` +
    `player.addEventListener(Twitch.Player.ONLINE,function(){post("playing");});});` +
    `window.embrPlayer={play:function(){if(player)player.play();},` +
    `pause:function(){if(player)player.pause();},` +
    `setMuted:function(m){if(player)player.setMuted(m);}};` +
    `</script></body></html>`
  );
}

/// Clips are not supported by the interactive embed, so they use Twitch's dedicated
/// official clip embed iframe.
function clipEmbed(clip: string, parent: string, muted: boolean): string {
  const src =
    `https://clips.twitch.tv/embed?clip=${encodeURIComponent(clip)}&parent=${encodeURIComponent(parent)}` +
    `&autoplay=true&muted=${muted ? 'true' : 'false'}`;
  return (
    EMBED_HEAD +
    `<body><iframe src="${src}" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>` +
    `</body></html>`
  );
}

app.get('/embed', (c) => {
  const host = new URL(c.req.url).hostname;
  if (!SAFE_HOST.test(host)) return fail(400, 'bad host');
  const muted = c.req.query('muted') === 'true';
  const channel = c.req.query('channel');
  const video = c.req.query('video');
  const clip = c.req.query('clip');

  if (clip) {
    if (!CLIP_RE.test(clip)) return fail(400, 'invalid clip');
    return htmlResponse(clipEmbed(clip, host, muted));
  }
  if (channel) {
    if (!CHANNEL_RE.test(channel)) return fail(400, 'invalid channel');
    return htmlResponse(interactiveEmbed(`channel:${jsString(channel)}`, host, muted));
  }
  if (video) {
    if (!VIDEO_RE.test(video)) return fail(400, 'invalid video');
    return htmlResponse(interactiveEmbed(`video:${jsString(video)}`, host, muted));
  }
  return fail(400, 'channel, video, or clip is required');
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
