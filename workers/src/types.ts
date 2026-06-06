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

export interface PollChoiceDTO {
  title: string;
  votes: number;
}

export interface PollDTO {
  id: string;
  title: string;
  status: string;
  endsAt: number;
  totalVotes: number;
  choices: PollChoiceDTO[];
}

export interface PredictionOutcomeDTO {
  title: string;
  color: string;
  points: number;
  users: number;
}

export interface PredictionDTO {
  id: string;
  title: string;
  status: string;
  locksAt: number;
  outcomes: PredictionOutcomeDTO[];
}

export interface ChannelEventsResponse {
  poll: PollDTO | null;
  prediction: PredictionDTO | null;
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

export const POLL_CONTEXT_SHA256 =
  "e83188a3836c636393df3191665e543a03733d7c51d3ade3d85e42aa46c2bf55";

export const PREDICTION_CONTEXT_SHA256 =
  "beb846598256b75bd7c1fe54a80431335996153e358ca9c7837ce7bb83d7d383";
