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

function makeEnv(store = new Map<string, string>(), adminToken?: string): Bindings {
  const env: Bindings = {
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
      list: async ({ prefix = '', limit = 1000, cursor }: { prefix?: string; limit?: number; cursor?: string } = {}) => {
        const all = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor ? Number(cursor) : 0;
        const slice = all.slice(start, start + limit);
        const next = start + limit;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({ name })),
          list_complete: complete,
          cacheStatus: null,
          ...(complete ? {} : { cursor: String(next) }),
        };
      },
    } as unknown as KVNamespace,
  };
  if (adminToken !== undefined) env.REPORTS_ADMIN_TOKEN = adminToken;
  return env;
}

function makeCtx(): { ctx: ExecutionContext; flush: () => Promise<void> } {
  const pending: Promise<unknown>[] = [];
  const ctx = {
    waitUntil: (promise: Promise<unknown>) => {
      pending.push(promise);
    },
    passThroughOnException: () => {},
    props: {},
  } as unknown as ExecutionContext;
  return {
    ctx,
    flush: async () => {
      await Promise.all(pending.splice(0));
    },
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

  it('propagates a non-2xx with a generic error body when Twitch rejects the code', async () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
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
    expect(body.error).toBe('upstream request failed (400)');
    expect(body.error).not.toContain('Invalid authorization code');
    expect(errorSpy).toHaveBeenCalled();
    expect(String(errorSpy.mock.calls[0]?.[0])).toContain('Invalid authorization code');
  });
});

describe('POST /auth/refresh', () => {
  it('refreshes the token and enriches from validate', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('/oauth2/token')) {
        return jsonResponse({
          access_token: 'newacc',
          refresh_token: 'newref',
          expires_in: 12000,
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
          expires_in: 12000,
        });
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request(
      '/auth/refresh',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: 'oldref' }),
      },
      makeEnv(),
    );

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      accessToken: 'newacc',
      refreshToken: 'newref',
      expiresIn: 12000,
      scope: ['user:read:chat'],
      userID: '12345',
      login: 'cooluser',
    });
    const tokenCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('/oauth2/token'));
    const sentBody = String((tokenCall?.[1] as RequestInit).body);
    expect(sentBody).toContain('grant_type=refresh_token');
    expect(sentBody).toContain('refresh_token=oldref');
  });

  it('returns 400 without a refreshToken', async () => {
    const res = await app.request(
      '/auth/refresh',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) },
      makeEnv(),
    );
    expect(res.status).toBe(400);
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
    expect(scope).toContain('moderator:manage:banned_users');
    expect(scope).toContain('moderator:manage:chat_messages');
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
    const cached = (await res2.json()) as { accessToken: string; expiresIn: number };
    expect(cached.accessToken).toBe('app-acc');
    expect(cached.expiresIn).toBeGreaterThan(0);
    expect(cached.expiresIn).toBeLessThanOrEqual(5000);
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
      if (url.includes('usher.ttvnw.net')) {
        return textResponse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunked.m3u8');
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
    expect(payload.variables.platform).toBe('web');
  });

  it('returns a non-2xx with error when GQL has no token', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ data: { streamPlaybackAccessToken: null } }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/ghost', {}, makeEnv());
    expect(res.status).toBe(404);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBeTruthy();
  });

  it('returns 404 when the channel is offline (usher 404s despite a minted token)', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        return jsonResponse({
          data: { streamPlaybackAccessToken: { value: '{"token":1}', signature: 'sig' } },
        });
      }
      if (url.includes('usher.ttvnw.net')) {
        return textResponse('not found', 404);
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/offlinechannel', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('falls back to the full GraphQL query when the persisted hash is rotated', async () => {
    let gqlCalls = 0;
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        gqlCalls += 1;
        if (gqlCalls === 1) {
          return jsonResponse({ errors: [{ message: 'PersistedQueryNotFound' }] });
        }
        return jsonResponse({
          data: { streamPlaybackAccessToken: { value: '{"token":1}', signature: 'sig' } },
        });
      }
      if (url.includes('usher.ttvnw.net')) {
        return textResponse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunked.m3u8');
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/rotated', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(gqlCalls).toBe(2);

    const secondGql = fetchMock.mock.calls.filter((c) => String(c[0]).includes('gql'))[1];
    const init = secondGql?.[1] as RequestInit;
    const payload = JSON.parse(String(init.body));
    expect(payload.query).toContain('PlaybackAccessToken_Template');
    expect(payload.extensions).toBeUndefined();
    expect((init.headers as Record<string, string>)['Device-ID']).toBeTruthy();
  });

  it('uses the KV-configured persisted-query hash when present', async () => {
    const store = new Map<string, string>();
    store.set('playback_token_sha256', 'deadbeefhash');
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        return jsonResponse({
          data: { streamPlaybackAccessToken: { value: '{"t":1}', signature: 's' } },
        });
      }
      if (url.includes('usher.ttvnw.net')) {
        return textResponse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunked.m3u8');
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/chan', {}, makeEnv(store));
    expect(res.status).toBe(200);
    const gqlCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('gql'));
    const payload = JSON.parse(String((gqlCall?.[1] as RequestInit).body));
    expect(payload.extensions.persistedQuery.sha256Hash).toBe('deadbeefhash');
  });

  it('falls back to the default persisted-query hash when the KV value is empty', async () => {
    const store = new Map<string, string>();
    store.set('playback_token_sha256', '');
    const fetchMock = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        return jsonResponse({
          data: { streamPlaybackAccessToken: { value: '{"t":1}', signature: 's' } },
        });
      }
      if (url.includes('usher.ttvnw.net')) {
        return textResponse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunked.m3u8');
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/chan', {}, makeEnv(store));
    expect(res.status).toBe(200);
    const gqlCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('gql'));
    const payload = JSON.parse(String((gqlCall?.[1] as RequestInit).body));
    expect(payload.extensions.persistedQuery.sha256Hash).toBe(
      'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9',
    );
  });

  it('rejects an invalid channel login with 400 before any upstream call', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    for (const login of ['bad!name', 'has space', 'a'.repeat(26), 'semi;colon']) {
      const res = await app.request(`http://embr.test/playback/${encodeURIComponent(login)}`, {}, makeEnv());
      expect(res.status, login).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects a non-numeric VOD id with 400', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const res = await app.request('http://embr.test/playback/vod/abc123', {}, makeEnv());
    expect(res.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns 504 when the usher preflight times out', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (url.includes('gql.twitch.tv/gql')) {
        return jsonResponse({
          data: { streamPlaybackAccessToken: { value: '{"token":1}', signature: 'sig' } },
        });
      }
      throw new DOMException('The operation timed out.', 'TimeoutError');
    });
    vi.stubGlobal('fetch', fetchMock);
    const res = await app.request('http://embr.test/playback/slowchannel', {}, makeEnv());
    expect(res.status).toBe(504);
  });
});

describe('GET /playback/clip/:slug', () => {
  const clipToken = { signature: 'clipsig', value: '{"clip_uri":"","expires":9999}' };
  const qualities = [
    { frameRate: 30, quality: '480', sourceURL: 'https://production.assets.clips.twitchcdn.net/abc-480.mp4' },
    { frameRate: 60, quality: '1080', sourceURL: 'https://production.assets.clips.twitchcdn.net/abc-1080.mp4' },
    { frameRate: 30, quality: '720', sourceURL: 'https://production.assets.clips.twitchcdn.net/abc-720.mp4' },
  ];

  it('resolves the highest-quality signed MP4 URL', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) =>
      jsonResponse({ data: { clip: { playbackAccessToken: clipToken, videoQualities: qualities } } }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/clip/CoolClip-slug_123', {}, makeEnv());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { url: string; qualities: Array<{ quality: string; url: string }> };
    expect(body.url).toBe(
      'https://production.assets.clips.twitchcdn.net/abc-1080.mp4' +
        `?sig=clipsig&token=${encodeURIComponent(clipToken.value)}`,
    );
    expect(body.qualities.map((q) => q.quality)).toEqual(['1080', '720', '480']);

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit;
    const headers = init.headers as Record<string, string>;
    expect(headers['Client-ID']).toBe('kimne78kx3ncx6brgo4mv6wki5h1ko');
    const payload = JSON.parse(String(init.body));
    expect(payload.operationName).toBe('VideoAccessToken_Clip');
    expect(payload.variables).toEqual({ slug: 'CoolClip-slug_123' });
    expect(payload.query).toContain('clip(slug: $slug)');
  });

  it('returns 404 when the clip does not exist', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ data: { clip: null } }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/clip/MissingClip', {}, makeEnv());
    expect(res.status).toBe(404);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBeTruthy();
  });

  it('returns 404 when the playbackAccessToken is null', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ data: { clip: { playbackAccessToken: null, videoQualities: qualities } } }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/clip/TokenlessClip', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('returns 404 when the clip has no playable qualities', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ data: { clip: { playbackAccessToken: clipToken, videoQualities: [] } } }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/clip/EmptyClip', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('surfaces a GQL error as 502 with the upstream message', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.fn(async () => jsonResponse({ errors: [{ message: 'service error' }] }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await app.request('http://embr.test/playback/clip/BrokenClip', {}, makeEnv());
    expect(res.status).toBe(502);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('service error');
  });

  it('rejects an invalid slug with 400 before any upstream call', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    for (const slug of ['-leadinghyphen', 'has space', 'a'.repeat(101), 'semi;colon']) {
      const res = await app.request(`http://embr.test/playback/clip/${encodeURIComponent(slug)}`, {}, makeEnv());
      expect(res.status, slug).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns 504 when the clip GQL request times out', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.fn(async () => {
      throw new DOMException('The operation timed out.', 'TimeoutError');
    });
    vi.stubGlobal('fetch', fetchMock);
    const res = await app.request('http://embr.test/playback/clip/SlowClip', {}, makeEnv());
    expect(res.status).toBe(504);
  });
});

describe('GET /config', () => {
  it('defaults to the native player when no switch is set', async () => {
    const res = await app.request('http://embr.test/config', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(await res.json()).toEqual({ livePlayback: 'native' });
  });

  it('serves the embed switch from KV', async () => {
    const env = makeEnv(new Map([['config:livePlayback', 'embed']]));
    const res = await app.request('http://embr.test/config', {}, env);
    expect(await res.json()).toEqual({ livePlayback: 'embed' });
  });

  it('treats any other stored value as native', async () => {
    const env = makeEnv(new Map([['config:livePlayback', 'hologram']]));
    const res = await app.request('http://embr.test/config', {}, env);
    expect(await res.json()).toEqual({ livePlayback: 'native' });
  });

  it('answers native when the KV read fails', async () => {
    const env = makeEnv();
    env.TOKENS.get = (async () => {
      throw new Error('kv down');
    }) as unknown as KVNamespace['get'];
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const res = await app.request('http://embr.test/config', {}, env);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ livePlayback: 'native' });
  });
});

describe('GET /events/:login', () => {
  it('rejects an invalid channel login with 400', async () => {
    const res = await app.request('http://embr.test/events/bad%20name', {}, makeEnv());
    expect(res.status).toBe(400);
  });
});

describe('GET /embed', () => {
  it('rejects an invalid channel with 400', async () => {
    const res = await app.request('http://embr.test/embed?channel=%22%3E%3Cscript%3E', {}, makeEnv());
    expect(res.status).toBe(400);
  });

  it('serves the scriptable Twitch player with this worker host as parent', async () => {
    const res = await app.request('http://embr.test/embed?channel=somechannel', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/html');
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    const html = await res.text();
    expect(html).toContain('https://player.twitch.tv/js/embed/v1.js');
    expect(html).toContain('"channel":"somechannel"');
    expect(html).toContain('"parent":["embr.test"]');
    expect(html).toContain('"muted":false');
  });

  it('reports player state to the app and exposes its controls', async () => {
    const res = await app.request('http://embr.test/embed?channel=somechannel&muted=true', {}, makeEnv());
    const html = await res.text();
    expect(html).toContain('"muted":true');
    expect(html).toContain('messageHandlers.embrPlayer.postMessage');
    for (const event of ['E.PLAYING', 'E.PAUSE', 'E.ENDED', 'E.OFFLINE']) {
      expect(html).toContain(event);
    }
    for (const control of ['play:', 'pause:', 'setMuted:', 'setQuality:']) {
      expect(html).toContain(control);
    }
  });

  it('builds the player frame without a sandbox so it can autoplay with sound', async () => {
    const res = await app.request('http://embr.test/embed?channel=somechannel', {}, makeEnv());
    const html = await res.text();
    expect(html).toContain("if(name==='sandbox'){return;}");
    expect(html).toContain('autoplay; fullscreen; picture-in-picture');
    expect(html.indexOf('document.createElement=function')).toBeLessThan(html.indexOf("new E('player'"));
    expect(html).toContain('document.createElement=make;');
  });

  it('returns 400 without a channel', async () => {
    const res = await app.request('http://embr.test/embed', {}, makeEnv());
    expect(res.status).toBe(400);
  });
});

describe('GET /hls/proxy', () => {
  it('strips ads from a media playlist and serves segments as direct CDN URLs', async () => {
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
    expect(text).toContain('https://usher.ttvnw.net/api/channel/hls/seg0.ts');
    expect(text).toContain('https://usher.ttvnw.net/api/channel/hls/seg1.ts');
    expect(text).not.toContain('/hls/proxy');
  });

  it('passes through the original playlist when stripping would leave no segments', async () => {
    const upstream = [
      '#EXTM3U',
      '#EXT-X-TARGETDURATION:2',
      '#EXT-X-MEDIA-SEQUENCE:0',
      '#EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",START-DATE="2024-01-01T00:00:00Z"',
      '#EXTINF:2.000,Amazon',
      'https://cdn.example/ad0.ts',
      '#EXTINF:2.000,Amazon',
      'https://cdn.example/ad1.ts',
    ].join('\n');
    vi.stubGlobal('fetch', vi.fn(async () => textResponse(upstream)));

    const src = 'https://usher.ttvnw.net/api/channel/hls/foo.m3u8';
    const res = await app.request(`http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`, {}, makeEnv());
    const text = await res.text();
    expect(res.status).toBe(200);
    expect(text).toContain('https://cdn.example/ad0.ts');
    expect(text).toContain('https://cdn.example/ad1.ts');
    expect(text).not.toContain('/hls/proxy');
  });

  it('returns 400 without a src', async () => {
    const res = await app.request('http://embr.test/hls/proxy', {}, makeEnv());
    expect(res.status).toBe(400);
  });

  it('allows Twitch HLS hosts through the allowlist', async () => {
    const fetchMock = vi.fn(async () => textResponse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunked.m3u8'));
    vi.stubGlobal('fetch', fetchMock);
    const allowed = [
      'https://usher.ttvnw.net/api/channel/hls/foo.m3u8',
      'https://video-weaver.hel01.hls.ttvnw.net/v1/playlist/abc.m3u8',
      'https://video-edge-abc.arn01.abs.hls.ttvnw.net/v1/segment/x.ts',
      'https://d2nvs31859zcd8.cloudfront.net/vod/chunked/0.m3u8',
      'https://clips-media-assets2.twitch.tv/foo.m3u8',
      'https://assets.twitchcdn.net/foo.m3u8',
      'https://video-edge.abc.twitchcdn.net/v1/segment/x.ts',
    ];
    for (const src of allowed) {
      const res = await app.request(`http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`, {}, makeEnv());
      expect(res.status, src).toBe(200);
    }
  });

  it('rejects non-allowlisted hosts with 403 without fetching them', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.fn(async () => textResponse('#EXTM3U'));
    vi.stubGlobal('fetch', fetchMock);
    const blocked = [
      'https://evil.example/steal',
      'https://ttvnw.net.evil.example/x.m3u8',
      'https://notttvnw.net/x.m3u8',
      'https://twitchcdn.net.evil.example/x.m3u8',
      'https://cloudfront.net.attacker.io/x.m3u8',
      'https://169.254.169.254/latest/meta-data',
      'http://usher.ttvnw.net/api/channel/hls/foo.m3u8',
    ];
    for (const src of blocked) {
      const res = await app.request(`http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`, {}, makeEnv());
      expect(res.status, src).toBe(403);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns 504 when the upstream fetch times out', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const timeoutError = new DOMException('The operation timed out.', 'TimeoutError');
    vi.stubGlobal('fetch', vi.fn(async () => { throw timeoutError; }));
    const src = 'https://usher.ttvnw.net/api/channel/hls/foo.m3u8';
    const res = await app.request(`http://embr.test/hls/proxy?src=${encodeURIComponent(src)}`, {}, makeEnv());
    expect(res.status).toBe(504);
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

describe('GET /auth/callback', () => {
  it('302-redirects Twitch HTTPS callback to the app custom scheme, forwarding code and state', async () => {
    const res = await app.request('http://embr.test/auth/callback?code=abc123&state=xyz', {}, makeEnv());
    expect(res.status).toBe(302);
    const location = res.headers.get('Location') ?? '';
    expect(location.startsWith('embr://auth/callback')).toBe(true);
    expect(location).toContain('code=abc123');
    expect(location).toContain('state=xyz');
  });
});

describe('POST /report', () => {
  it('stores a report in KV (capped) and returns 204', async () => {
    const store = new Map<string, string>();
    const { ctx, flush } = makeCtx();
    const res = await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ authorID: 'u1', authorLogin: 'baduser', reason: 'Harassment', text: 'x'.repeat(5000) }),
      },
      makeEnv(store),
      ctx,
    );
    expect(res.status).toBe(204);
    await flush();
    const stored = [...store.entries()].find(([k]) => k.startsWith('report:'));
    expect(stored).toBeDefined();
    const payload = JSON.parse(stored![1]);
    expect(payload.reason).toBe('Harassment');
    expect(payload.text.length).toBe(2000);
    expect(payload.kind).toBe('report');
  });

  it('tags a block as kind "block"', async () => {
    const store = new Map<string, string>();
    const { ctx, flush } = makeCtx();
    const res = await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ authorID: 'u9', authorLogin: 'meanie', reason: 'Blocked abusive user' }),
      },
      makeEnv(store),
      ctx,
    );
    expect(res.status).toBe(204);
    await flush();
    const stored = [...store.entries()].find(([k]) => k.startsWith('report:'));
    expect(JSON.parse(stored![1]).kind).toBe('block');
  });

  it('returns 400 when reason or target is missing', async () => {
    const res = await app.request(
      'http://embr.test/report',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ channel: 'c' }) },
      makeEnv(),
      makeCtx().ctx,
    );
    expect(res.status).toBe(400);
  });

  it('returns 400 on a non-JSON body', async () => {
    const res = await app.request(
      'http://embr.test/report',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'not json' },
      makeEnv(),
      makeCtx().ctx,
    );
    expect(res.status).toBe(400);
  });

  it('returns 413 when the body exceeds the size cap', async () => {
    const res = await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ authorID: 'u1', reason: 'Spam', text: 'x'.repeat(9000) }),
      },
      makeEnv(),
      makeCtx().ctx,
    );
    expect(res.status).toBe(413);
  });

  it('returns 413 when multi-byte characters push the byte size past the cap', async () => {
    const store = new Map<string, string>();
    const body = JSON.stringify({ authorID: 'u1', reason: 'Spam', text: '€'.repeat(3000) });
    expect(body.length).toBeLessThanOrEqual(8192);
    expect(new TextEncoder().encode(body).length).toBeGreaterThan(8192);
    const res = await app.request(
      'http://embr.test/report',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body },
      makeEnv(store),
      makeCtx().ctx,
    );
    expect(res.status).toBe(413);
    expect([...store.keys()].some((k) => k.startsWith('report:'))).toBe(false);
  });

  it('returns 413 from the Content-Length header alone', async () => {
    const res = await app.request(
      new Request('http://embr.test/report', {
        method: 'GET',
        headers: { 'Content-Type': 'application/json', 'Content-Length': '999999' },
      }),
      { method: 'POST', body: JSON.stringify({ authorID: 'u1', reason: 'Spam' }) },
      makeEnv(),
      makeCtx().ctx,
    );
    expect(res.status).toBe(413);
  });

  it('rate limits a client IP to 5 reports per window with 429', async () => {
    const store = new Map<string, string>();
    const env = makeEnv(store);
    const send = async () => {
      const { ctx, flush } = makeCtx();
      const res = await app.request(
        'http://embr.test/report',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '203.0.113.7' },
          body: JSON.stringify({ authorID: 'u1', reason: 'Spam' }),
        },
        env,
        ctx,
      );
      await flush();
      return res;
    };
    for (let i = 0; i < 5; i++) {
      expect((await send()).status).toBe(204);
    }
    expect((await send()).status).toBe(429);
    expect([...store.keys()].filter((k) => k.startsWith('report:')).length).toBe(5);
  });

  it('tracks rate limits per client IP independently', async () => {
    const store = new Map<string, string>();
    const env = makeEnv(store);
    const send = async (ip: string) => {
      const { ctx, flush } = makeCtx();
      const res = await app.request(
        'http://embr.test/report',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip },
          body: JSON.stringify({ authorID: 'u1', reason: 'Spam' }),
        },
        env,
        ctx,
      );
      await flush();
      return res;
    };
    for (let i = 0; i < 5; i++) await send('198.51.100.1');
    expect((await send('198.51.100.1')).status).toBe(429);
    expect((await send('198.51.100.2')).status).toBe(204);
  });
});

describe('GET /reports', () => {
  it('is disabled (404) when no admin token is configured', async () => {
    const res = await app.request('http://embr.test/reports', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('rejects a missing or wrong bearer token with 401', async () => {
    const store = new Map<string, string>();
    const noAuth = await app.request('http://embr.test/reports', {}, makeEnv(store, 'secret'));
    expect(noAuth.status).toBe(401);
    const wrong = await app.request(
      'http://embr.test/reports',
      { headers: { Authorization: 'Bearer nope' } },
      makeEnv(store, 'secret'),
    );
    expect(wrong.status).toBe(401);
  });

  it('lists stored reports newest-first for an authorized reviewer', async () => {
    const store = new Map<string, string>();
    store.set('report:100-a', JSON.stringify({ reason: 'Spam', authorLogin: 'old', at: 100 }));
    store.set('report:200-b', JSON.stringify({ reason: 'Harassment', authorLogin: 'new', at: 200 }));
    store.set('app_token', JSON.stringify({ accessToken: 'x', expiresAt: 999 }));
    const res = await app.request(
      'http://embr.test/reports',
      { headers: { Authorization: 'Bearer secret' } },
      makeEnv(store, 'secret'),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { count: number; reports: Array<{ authorLogin: string }> };
    expect(body.count).toBe(2);
    expect(body.reports[0]?.authorLogin).toBe('new');
    expect(body.reports[1]?.authorLogin).toBe('old');
  });

  it('paginates past 1000 keys so the newest reports are not dropped', async () => {
    const store = new Map<string, string>();
    const total = 1500;
    for (let i = 0; i < total; i++) {
      store.set(`report:${1_000_000 + i}-x`, JSON.stringify({ authorLogin: `u${i}`, at: 1_000_000 + i }));
    }
    const res = await app.request(
      'http://embr.test/reports',
      { headers: { Authorization: 'Bearer secret' } },
      makeEnv(store, 'secret'),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { count: number; reports: Array<{ at: number }> };
    expect(body.count).toBe(total);
    expect(body.reports[0]?.at).toBe(1_000_000 + total - 1);
  });
});

describe('legal pages', () => {
  it('serves the terms page with the zero-tolerance clause', async () => {
    const res = await app.request('http://embr.test/legal/terms', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/html');
    expect((await res.text()).toLowerCase()).toContain('zero tolerance');
  });

  it('serves the privacy page', async () => {
    const res = await app.request('http://embr.test/legal/privacy', {}, makeEnv());
    expect(res.status).toBe(200);
    expect((await res.text()).toLowerCase()).toContain('privacy');
  });
});
