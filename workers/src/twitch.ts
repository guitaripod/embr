import {
  GQL_CLIENT_ID,
  PLAYBACK_ACCESS_TOKEN_SHA256,
  POLL_CONTEXT_SHA256,
  PREDICTION_CONTEXT_SHA256,
  type ChannelEventsResponse,
  type PollDTO,
  type PredictionDTO,
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
    platform: 'web',
  };
}

interface GQLPlaybackResponse {
  data?: {
    streamPlaybackAccessToken?: { value: string; signature: string } | null;
    videoPlaybackAccessToken?: { value: string; signature: string } | null;
  };
  errors?: Array<{ message?: string }>;
}

const PLAYBACK_FULL_QUERY =
  'query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!, $platform: String!) {' +
  '  streamPlaybackAccessToken(channelName: $login, params: {platform: $platform, playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isLive) { value signature __typename }' +
  '  videoPlaybackAccessToken(id: $vodID, params: {platform: $platform, playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isVod) { value signature __typename }' +
  '}';

function deviceID(): string {
  return crypto.randomUUID().replace(/-/g, '');
}

function playbackPayload(kind: PlaybackKind, persisted: boolean, hash: string): Record<string, unknown> {
  if (persisted) {
    return {
      operationName: 'PlaybackAccessToken',
      variables: playbackVariables(kind),
      extensions: { persistedQuery: { version: 1, sha256Hash: hash } },
    };
  }
  return {
    operationName: 'PlaybackAccessToken_Template',
    query: PLAYBACK_FULL_QUERY,
    variables: playbackVariables(kind),
  };
}

interface PlaybackTokenResult {
  token?: { value: string; signature: string };
  persistedMiss: boolean;
}

async function requestPlaybackToken(kind: PlaybackKind, persisted: boolean, hash: string): Promise<PlaybackTokenResult> {
  const res = await fetch(GQL_URL, {
    method: 'POST',
    headers: {
      'Client-ID': GQL_CLIENT_ID,
      'Content-Type': 'application/json',
      'Device-ID': deviceID(),
    },
    body: JSON.stringify(playbackPayload(kind, persisted, hash)),
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  const json = (await res.json()) as GQLPlaybackResponse;
  if (json.errors && json.errors.length > 0) {
    const message = json.errors[0]?.message ?? 'gql playback error';
    if (message.toLowerCase().includes('persistedquerynotfound')) {
      return { persistedMiss: true };
    }
    throw new TwitchError(message, 502);
  }
  const token =
    kind.type === 'live'
      ? json.data?.streamPlaybackAccessToken
      : json.data?.videoPlaybackAccessToken;
  return { token: token ?? undefined, persistedMiss: false };
}

/// Mints a PlaybackAccessToken, retrying with the full GraphQL query if the
/// persisted-query hash has rotated (Twitch changes it without notice), so the
/// anonymous fallback path keeps working without a redeploy.
export async function fetchPlaybackAccessToken(
  kind: PlaybackKind,
  hashOverride?: string,
): Promise<PlaybackAccessToken> {
  const hash = hashOverride && hashOverride.length > 0 ? hashOverride : PLAYBACK_ACCESS_TOKEN_SHA256;
  let result = await requestPlaybackToken(kind, true, hash);
  if (result.persistedMiss) {
    result = await requestPlaybackToken(kind, false, hash);
  }
  if (!result.token) throw new TwitchError('playback access token unavailable', 404);
  return { value: result.token.value, signature: result.token.signature };
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

async function gqlPersisted(
  operationName: string,
  variables: Record<string, unknown>,
  hash: string,
): Promise<unknown> {
  const res = await fetch(GQL_URL, {
    method: 'POST',
    headers: { 'Client-ID': GQL_CLIENT_ID, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      operationName,
      variables,
      extensions: { persistedQuery: { version: 1, sha256Hash: hash } },
    }),
  });
  if (!res.ok) throw new TwitchError(await readTwitchError(res), res.status);
  return await res.json();
}

function epochSeconds(iso: unknown): number {
  if (typeof iso !== 'string') return 0;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : 0;
}

function normalizePoll(raw: unknown): PollDTO | null {
  const poll = (raw as any)?.data?.channel?.viewablePoll;
  if (!poll || typeof poll.id !== 'string') return null;
  const status = String(poll.status ?? '');
  if (status !== 'ACTIVE') return null;
  const choices = Array.isArray(poll.choices) ? poll.choices : [];
  const mapped = choices.map((c: any) => ({
    title: String(c?.title ?? ''),
    votes: Number(c?.votes?.total ?? c?.totalVoters ?? 0),
  }));
  const started = epochSeconds(poll.startedAt);
  const duration = Number(poll.durationSeconds ?? 0);
  const endsAt = epochSeconds(poll.endedAt) || (started ? started + duration : 0);
  return {
    id: String(poll.id),
    title: String(poll.title ?? 'Poll'),
    status,
    endsAt,
    totalVotes: mapped.reduce((sum: number, c: { votes: number }) => sum + c.votes, 0),
    choices: mapped,
  };
}

function normalizePrediction(raw: unknown): PredictionDTO | null {
  const channel = (raw as any)?.data?.community?.channel;
  if (!channel) return null;
  const active = Array.isArray(channel.activePredictionEvents) ? channel.activePredictionEvents : [];
  const locked = Array.isArray(channel.lockedPredictionEvents) ? channel.lockedPredictionEvents : [];
  const event = active[0] ?? locked[0];
  if (!event || typeof event.id !== 'string') return null;
  const outcomes = Array.isArray(event.outcomes) ? event.outcomes : [];
  const created = epochSeconds(event.createdAt);
  const window = Number(event.predictionWindowSeconds ?? 0);
  const locksAt = epochSeconds(event.lockedAt) || (created ? created + window : 0);
  return {
    id: String(event.id),
    title: String(event.title ?? 'Prediction'),
    status: String(event.status ?? ''),
    locksAt,
    outcomes: outcomes.map((o: any) => ({
      title: String(o?.title ?? ''),
      color: String(o?.color ?? 'BLUE'),
      points: Number(o?.totalPoints ?? 0),
      users: Number(o?.totalUsers ?? 0),
    })),
  };
}

export async function fetchChannelEvents(login: string): Promise<ChannelEventsResponse> {
  const [pollRes, predRes] = await Promise.allSettled([
    gqlPersisted('ChannelPollContext_GetViewablePoll', { login }, POLL_CONTEXT_SHA256),
    gqlPersisted('ChannelPointsPredictionContext', { count: 1, channelLogin: login }, PREDICTION_CONTEXT_SHA256),
  ]);
  const safe = <T>(fn: () => T): T | null => {
    try {
      return fn();
    } catch {
      return null;
    }
  };
  return {
    poll: pollRes.status === 'fulfilled' ? safe(() => normalizePoll(pollRes.value)) : null,
    prediction: predRes.status === 'fulfilled' ? safe(() => normalizePrediction(predRes.value)) : null,
  };
}

export async function resolveLivePlayback(login: string, hashOverride?: string): Promise<string> {
  const token = await fetchPlaybackAccessToken({ type: 'live', login }, hashOverride);
  return buildUsherURL({ type: 'live', login }, token);
}

export async function resolveVodPlayback(id: string, hashOverride?: string): Promise<string> {
  const token = await fetchPlaybackAccessToken({ type: 'vod', id }, hashOverride);
  return buildUsherURL({ type: 'vod', id }, token);
}
