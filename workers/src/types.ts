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

export interface ErrorResponse {
  error: string;
}

export interface ReportRequest {
  channel?: string;
  messageID?: string;
  authorID?: string;
  authorLogin?: string;
  reason?: string;
  text?: string;
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
  "user:manage:chat_color",
  "moderator:manage:banned_users",
  "moderator:manage:chat_messages",
] as const;

export const REPORT_KV_PREFIX = "report:";
export const REPORT_TTL_SECONDS = 60 * 60 * 24 * 30;
