import { afterEach, describe, expect, it, vi } from 'vitest';
import app from '../src/index';
import type { Bindings } from '../src/types';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
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
      list: async () => ({
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
        cursor: '',
      }),
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
    expect(scope).toContain('user:manage:chat_color');
    expect(scope).toContain('moderator:manage:banned_users');
    expect(scope).toContain('moderator:manage:chat_messages');
  });

  it('does not request the unused blocked-users scopes', async () => {
    const res = await app.request('/auth/login-url?redirectURI=embr%3A%2F%2Fcb', {}, makeEnv());
    const body = (await res.json()) as { url: string };
    const scope = new URL(body.url).searchParams.get('scope') ?? '';
    expect(scope).not.toContain('blocked_users');
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

describe('GET /embed', () => {
  it('serves the official Twitch interactive embed for a channel with this worker host as parent', async () => {
    const res = await app.request('http://embr.test/embed?channel=somechannel', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/html');
    const html = await res.text();
    expect(html).toContain('embed.twitch.tv/embed/v1.js');
    expect(html).toContain('channel:"somechannel"');
    expect(html).toContain('parent:["embr.test"]');
    expect(html).toContain('layout:"video"');
  });

  it('serves the interactive embed for a VOD', async () => {
    const res = await app.request('http://embr.test/embed?video=123456789', {}, makeEnv());
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('embed.twitch.tv/embed/v1.js');
    expect(html).toContain('video:"123456789"');
  });

  it('serves the official clip embed for a clip slug', async () => {
    const res = await app.request('http://embr.test/embed?clip=HappyClipSlug', {}, makeEnv());
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('clips.twitch.tv/embed?clip=HappyClipSlug');
    expect(html).toContain('parent=embr.test');
  });

  it('does not strip ads or touch any unofficial Twitch endpoint', async () => {
    const res = await app.request('http://embr.test/embed?channel=foo', {}, makeEnv());
    const html = await res.text();
    expect(html).not.toContain('usher');
    expect(html).not.toContain('kimne78');
    expect(html).not.toContain('stitched');
  });

  it('rejects a script-injection attempt in channel and never emits a closing script tag from input', async () => {
    const res = await app.request(
      'http://embr.test/embed?channel=' + encodeURIComponent('</script><script>alert(1)</script>'),
      {},
      makeEnv(),
    );
    expect(res.status).toBe(400);
  });

  it('rejects invalid video and clip ids', async () => {
    expect((await app.request('http://embr.test/embed?video=abc', {}, makeEnv())).status).toBe(400);
    expect((await app.request('http://embr.test/embed?clip=' + encodeURIComponent('a b/c'), {}, makeEnv())).status).toBe(400);
  });

  it('returns 400 without a target', async () => {
    const res = await app.request('http://embr.test/embed', {}, makeEnv());
    expect(res.status).toBe(400);
  });
});

describe('POST /report', () => {
  it('stores a report in KV and returns 204', async () => {
    const store = new Map<string, string>();
    const res = await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          channel: 'somechannel',
          messageID: 'm1',
          authorID: 'u1',
          authorLogin: 'baduser',
          reason: 'Harassment',
          text: 'something bad',
        }),
      },
      makeEnv(store),
    );
    expect(res.status).toBe(204);
    const stored = [...store.entries()].find(([k]) => k.startsWith('report:'));
    expect(stored).toBeDefined();
    const payload = JSON.parse(stored![1]);
    expect(payload.reason).toBe('Harassment');
    expect(payload.authorLogin).toBe('baduser');
  });

  it('returns 400 when reason or target is missing', async () => {
    const res = await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel: 'somechannel' }),
      },
      makeEnv(),
    );
    expect(res.status).toBe(400);
  });

  it('returns 400 on a non-JSON body', async () => {
    const res = await app.request(
      'http://embr.test/report',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'not json' },
      makeEnv(),
    );
    expect(res.status).toBe(400);
  });

  it('caps an oversized report text before storing', async () => {
    const store = new Map<string, string>();
    await app.request(
      'http://embr.test/report',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ authorID: 'u1', reason: 'Spam', text: 'x'.repeat(5000) }),
      },
      makeEnv(store),
    );
    const stored = [...store.values()].find((v) => v.includes('Spam'));
    const payload = JSON.parse(stored!);
    expect(payload.text.length).toBe(2000);
  });
});

describe('legal pages', () => {
  it('serves the terms page with the zero-tolerance clause', async () => {
    const res = await app.request('http://embr.test/legal/terms', {}, makeEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/html');
    const html = await res.text();
    expect(html.toLowerCase()).toContain('zero tolerance');
    expect(html).toContain('report');
  });

  it('serves the privacy page', async () => {
    const res = await app.request('http://embr.test/legal/privacy', {}, makeEnv());
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html.toLowerCase()).toContain('privacy');
  });
});

describe('removed non-compliant routes', () => {
  it('no longer serves /playback', async () => {
    const res = await app.request('http://embr.test/playback/somechannel', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('no longer serves /hls/proxy', async () => {
    const res = await app.request('http://embr.test/hls/proxy?src=https://x', {}, makeEnv());
    expect(res.status).toBe(404);
  });

  it('no longer serves /events', async () => {
    const res = await app.request('http://embr.test/events/somechannel', {}, makeEnv());
    expect(res.status).toBe(404);
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
