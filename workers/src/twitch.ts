import {
  GQL_CLIENT_ID,
  PLAYBACK_ACCESS_TOKEN_SHA256,
  type TwitchTokenPayload,
  type TwitchValidatePayload,
} from './types';

const TOKEN_URL = 'https://id.twitch.tv/oauth2/token';
const VALIDATE_URL = 'https://id.twitch.tv/oauth2/validate';
const AUTHORIZE_URL = 'https://id.twitch.tv/oauth2/authorize';
const GQL_URL = 'https://gql.twitch.tv/gql';

export class TwitchError extends Error {
  readonly status: number;
  constructor(message: string, status = 502) {
    super(message);
    this.name = 'TwitchError';
    this.status = status;
  }
}

async function readTwitchError(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as { message?: string; error?: string };
    return body.message ?? body.error ?? `twitch responded ${res.status}`;
  } catch {
    return `twitch responded ${res.status}`;
  }
}

export async function exchangeCode(
  clientID: string,
  clientSecret: string,
  code: string,
  redirectURI: string,
): Promise<TwitchTokenPayload> {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: clientID,
    client_secret: clientSecret,
    code,
    redirect_uri: redirectURI,
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  return (await res.json()) as TwitchTokenPayload;
}

export async function refreshToken(
  clientID: string,
  clientSecret: string,
  token: string,
): Promise<TwitchTokenPayload> {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: clientID,
    client_secret: clientSecret,
    refresh_token: token,
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  return (await res.json()) as TwitchTokenPayload;
}

export async function clientCredentials(
  clientID: string,
  clientSecret: string,
): Promise<TwitchTokenPayload> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: clientID,
    client_secret: clientSecret,
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  return (await res.json()) as TwitchTokenPayload;
}

export async function validateToken(accessToken: string): Promise<TwitchValidatePayload> {
  const res = await fetch(VALIDATE_URL, {
    headers: { Authorization: `OAuth ${accessToken}` },
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  return (await res.json()) as TwitchValidatePayload;
}

export function buildLoginURL(
  clientID: string,
  redirectURI: string,
  scopes: readonly string[],
  state: string | undefined,
): string {
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: clientID,
    redirect_uri: redirectURI,
    scope: scopes.join(' '),
    force_verify: 'true',
  });
  if (state !== undefined && state.length > 0) params.set('state', state);
  return `${AUTHORIZE_URL}?${params.toString()}`;
}

export interface PlaybackAccessToken {
  value: string;
  signature: string;
}

type PlaybackKind = { type: 'live'; login: string } | { type: 'vod'; id: string };

function playbackVariables(kind: PlaybackKind): Record<string, unknown> {
  return {
    isLive: kind.type === 'live',
    login: kind.type === 'live' ? kind.login : '',
    isVod: kind.type === 'vod',
    vodID: kind.type === 'vod' ? kind.id : '',
    playerType: 'site',
  };
}

interface GQLPlaybackResponse {
  data?: {
    streamPlaybackAccessToken?: { value: string; signature: string } | null;
    videoPlaybackAccessToken?: { value: string; signature: string } | null;
  };
  errors?: Array<{ message?: string }>;
}

export async function fetchPlaybackAccessToken(kind: PlaybackKind): Promise<PlaybackAccessToken> {
  const payload = {
    operationName: 'PlaybackAccessToken',
    variables: playbackVariables(kind),
    extensions: {
      persistedQuery: {
        version: 1,
        sha256Hash: PLAYBACK_ACCESS_TOKEN_SHA256,
      },
    },
  };
  const res = await fetch(GQL_URL, {
    method: 'POST',
    headers: {
      'Client-ID': GQL_CLIENT_ID,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  const json = (await res.json()) as GQLPlaybackResponse;
  if (json.errors && json.errors.length > 0) {
    throw new TwitchError(json.errors[0]?.message ?? 'gql playback error', 502);
  }
  const token =
    kind.type === 'live'
      ? json.data?.streamPlaybackAccessToken
      : json.data?.videoPlaybackAccessToken;
  if (!token) throw new TwitchError('playback access token unavailable', 404);
  return { value: token.value, signature: token.signature };
}

const USHER_LIVE = 'https://usher.ttvnw.net/api/channel/hls';
const USHER_VOD = 'https://usher.ttvnw.net/vod';

export function buildUsherURL(kind: PlaybackKind, token: PlaybackAccessToken): string {
  const params = new URLSearchParams({
    allow_source: 'true',
    allow_audio_only: 'true',
    fast_bread: 'true',
    'p': String(Math.floor(Math.random() * 1_000_000)),
    'play_session_id': crypto.randomUUID().replace(/-/g, ''),
    player: 'twitchweb',
    'supported_codecs': 'avc1',
    sig: token.signature,
    token: token.value,
    cdm: 'wv',
    'player_version': '1.0.0',
  });
  if (kind.type === 'live') {
    return `${USHER_LIVE}/${encodeURIComponent(kind.login)}.m3u8?${params.toString()}`;
  }
  return `${USHER_VOD}/${encodeURIComponent(kind.id)}.m3u8?${params.toString()}`;
}

export async function resolveLivePlayback(login: string): Promise<string> {
  const token = await fetchPlaybackAccessToken({ type: 'live', login });
  return buildUsherURL({ type: 'live', login }, token);
}

export async function resolveVodPlayback(id: string): Promise<string> {
  const token = await fetchPlaybackAccessToken({ type: 'vod', id });
  return buildUsherURL({ type: 'vod', id }, token);
}
