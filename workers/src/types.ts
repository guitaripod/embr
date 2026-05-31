export interface Bindings {
  TWITCH_CLIENT_ID: string;
  TWITCH_CLIENT_SECRET: string;
  TOKENS: KVNamespace;
}

export interface TokenResponse {
  accessToken: string;
  refreshToken?: string;
  expiresIn: number;
  scope?: string[];
  userID?: string;
  login?: string;
}

export interface AppTokenResponse {
  accessToken: string;
  expiresIn: number;
}

export interface LoginURLResponse {
  url: string;
}

export interface PlaybackResponse {
  url: string;
  expiresAt?: number;
}

export interface ErrorResponse {
  error: string;
}

export interface TwitchTokenPayload {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  scope?: string[];
  token_type: string;
}

export interface TwitchValidatePayload {
  client_id: string;
  login?: string;
  user_id?: string;
  scopes?: string[];
  expires_in: number;
}

export const VIEWER_SCOPES = [
  "user:read:chat",
  "user:write:chat",
  "user:read:follows",
  "user:read:blocked_users",
  "user:manage:blocked_users",
  "user:manage:chat_color",
] as const;

export const GQL_CLIENT_ID = "kimne78kx3ncx6brgo4mv6wki5h1ko";

export const PLAYBACK_ACCESS_TOKEN_SHA256 =
  "ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9";
