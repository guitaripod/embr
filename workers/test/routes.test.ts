import { afterEach, describe, expect, it, vi } from 'vitest';
import app from '../src/index';
import type { Bindings } from '../src/types';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function textResponse(body: string, status = 200): Response {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain' } });
}

function makeEnv(store = new Map<string, string>()): Bindings {
  return {
    TWITCH_CLIENT_ID: 'test-client-id',
    TWITCH_CLIENT_SECRET: 'test-client-secret',
    TOKENS: {
      get: async (key: string, type?: string) => {
        const raw = store.get(key);
        if (raw === undefined) return null;
        return type === 'json' ? JSON.parse(raw) : raw;
      },
      put: async (key: string, value: string) => {
        store.set(key, value);
      },
      delete: async (key: string) => {
        store.delete(key);
      },
    } as unknown as KVNamespace,
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('POST /auth/exchange', () => {
  it('exchanges the code and enriches userID/login from validate', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('/oauth2/token')) {
        return jsonResponse({
          access_token: 'acc',
          refresh_token: 'ref',
          expires_in: 14000,
          scope: ['user:read:chat'],
          token_type: 'bearer',
        });
      }
      if (url.includes('/oauth2/validate')) {
        return jsonResponse({
          client_id: 'test-client-id',
          login: 'cooluser',
          user_id: '12345',
          scopes: ['user:read:chat'],
          expires_in: 14000,
        });
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request(
      '/auth/exchange',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: 'authcode', redirectURI: 'embr://callback' }),
      },
      makeEnv(),
    );

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({
      accessToken: 'acc',
      refreshToken: 'ref',
      expiresIn: 14000,
      scope: ['user:read:chat'],
      userID: '12345',
      login: 'cooluser',
    });

    const tokenCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('/oauth2/token'));
    expect(tokenCall).toBeDefined();
    const init = tokenCall?.[1] as RequestInit;
    const sentBody = String(init.body);
    expect(sentBody).toContain('grant_type=authorization_code');
    expect(sentBody).toContain('client_id=test-client-id');
    expect(sentBody).toContain('client_secret=test-client-secret');
    expect(sentBody).toContain('code=authcode');
    expect(sentBody).toContain('redirect_uri=embr%3A%2F%2Fcallback');
  });

  it('returns 400 when fields are missing', async () => {
    const res = await app.request(
      '/auth/exchange',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: 'only' }),
      },
      makeEnv(),
    );
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBeTruthy();
  });

  it('propagates a non-2xx with an error body when Twitch rejects the code', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ message: 'Invalid authorization code' }, 400));
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request(
      '/auth/exchange',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: 'bad', redirectURI: 'embr://callback' }),
      },
      makeEnv(),
    );

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe('Invalid authorization code');
  });
});

describe('GET /auth/login-url', () => {
  it('builds the Twitch authorize URL with the viewer scopes', async () => {
    const res = await app.request(
      '/auth/login-url?redirectURI=embr%3A%2F%2Fcb&state=xyz',
      {},
      makeEnv(),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { url: string };
    const url = new URL(body.url);
    expect(url.origin + url.pathname).toBe('https://id.twitch.tv/oauth2/authorize');
    expect(url.searchParams.get('response_type')).toBe('code');
    expect(url.searchParams.get('client_id')).toBe('test-client-id');
    expect(url.searchParams.get('redirect_uri')).toBe('embr://cb');
    expect(url.searchParams.get('state')).toBe('xyz');
    expect(url.searchParams.get('force_verify')).toBe('true');
    const scope = url.searchParams.get('scope') ?? '';
    expect(scope).toContain('user:read:chat');
    expect(scope).toContain('user:write:chat');
    expect(scope).toContain('user:read:follows');
    expect(scope).toContain('user:read:blocked_users');
    expect(scope).toContain('user:manage:blocked_users');
    expect(scope).toContain('user:manage:chat_color');
  });

  it('returns 400 without redirectURI', async () => {
    const res = await app.request('/auth/login-url', {}, makeEnv());
    expect(res.status).toBe(400);
  });
});

describe('GET /auth/app-token', () => {
  it('mints and caches the app token in KV', async () => {
    const store = new Map<string, string>();
    const fetchMock = vi.fn(async () =>
      jsonResponse({ access_token: 'app-acc', expires_in: 5000, token_type: 'bearer' }),
    );
    vi.stubGlobal('fetch', fetchMock);
    const env = makeEnv(store);

    const res = await app.request('/auth/app-token', {}, env);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ accessToken: 'app-acc', expiresIn: 5000 });
    expect(store.has('app_token')).toBe(true);

    const res2 = await app.request('/auth/app-token', {}, env);
    expect(await res2.json()).toEqual({ accessToken: 'app-acc', expiresIn: 5000 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe('GET /playback/:login', () => {
  it('resolves a usher URL and returns a proxied url back to this worker', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        return jsonResponse({
          data: {
            streamPlaybackAccessToken: { value: '{"token":1}', signature: 'sig123' },
          },
        });
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/somechannel', {}, makeEnv());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { url: string; expiresAt?: number };
    expect(body.url.startsWith('http://embr.test/hls/proxy?src=')).toBe(true);
    const src = new URL(body.url).searchParams.get('src') ?? '';
    expect(src).toContain('usher.ttvnw.net');
    expect(src).toContain('somechannel.m3u8');

    const gqlCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('gql'));
    const init = gqlCall?.[1] as RequestInit;
    const headers = init.headers as Record<string, string>;
    expect(headers['Client-ID']).toBe('kimne78kx3ncx6brgo4mv6wki5h1ko');
    const payload = JSON.parse(String(init.body));
    expect(payload.extensions.persistedQuery.sha256Hash).toBe(
      'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9',
    );
    expect(payload.variables.isLive).toBe(true);
    expect(payload.variables.login).toBe('somechannel');
  });

  it('returns a non-2xx with error when GQL has no token', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ data: { streamPlaybackAccessToken: null } }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/ghost', {}, makeEnv());
    expect(res.status).toBe(404);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBeTruthy();
  });
});

describe('GET /hls/proxy', () => {
  it('strips ads from a media playlist and rewrites segment URIs through the proxy', async () => {
    const upstream = [
      '#EXTM3U',
      '#EXT-X-VERSION:6',
      '#EXT-X-TARGETDURATION:2',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",START-DATE="2024-01-01T00:00:00Z"',
      '#EXTINF:15.000,Amazon',
      'ad0.ts',
      '#EXTINF:2.000,live',
      'seg1.ts',
    ].join('\n');

    const fetchMock = vi.fn(async () => textResponse(upstream));
    vi.stubGlobal('fetch', fetchMock);

    const src = 'https://usher.ttvnw.net/api/channel/hls/foo.m3u8?sig=x';
    const res = await app.request(
      `http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`,
      {},
      makeEnv(),
    );

    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('application/vnd.apple.mpegurl');
    const text = await res.text();
    expect(text).not.toContain('ad0.ts');
    expect(text).not.toContain('Amazon');
    expect(text).not.toContain('twitch-stitched-ad');
    expect(text).toContain('#EXTINF:2.000,live');
    const seg0Abs = 'https://usher.ttvnw.net/api/channel/hls/seg0.ts';
    expect(text).toContain(`http://embr.test/hls/proxy?src=${encodeURIComponent(seg0Abs)}`);
  });

  it('returns 400 without a src', async () => {
    const res = await app.request('http://embr.test/hls/proxy', {}, makeEnv());
    expect(res.status).toBe(400);
  });

  it('rewrites variant URIs in a master playlist without stripping', async () => {
    const master = [
      '#EXTM3U',
      '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720',
      'https://video-weaver.example/720.m3u8',
    ].join('\n');
    const fetchMock = vi.fn(async () => textResponse(master));
    vi.stubGlobal('fetch', fetchMock);

    const src = 'https://usher.ttvnw.net/api/channel/hls/foo.m3u8';
    const res = await app.request(
      `http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`,
      {},
      makeEnv(),
    );
    const text = await res.text();
    const variantAbs = 'https://video-weaver.example/720.m3u8';
    expect(text).toContain(`http://embr.test/hls/proxy?src=${encodeURIComponent(variantAbs)}`);
  });
});
