import type { TwitchTokenPayload, TwitchValidatePayload } from './types';

const TOKEN_URL = 'https://id.twitch.tv/oauth2/token';
const VALIDATE_URL = 'https://id.twitch.tv/oauth2/validate';
const AUTHORIZE_URL = 'https://id.twitch.tv/oauth2/authorize';

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
