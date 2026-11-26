# Privacy

`embr` runs on your machine. It has no analytics, telemetry, crash reporting or advertising.

## What it stores

- Twitch access and refresh tokens in `${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json`, mode
  `0600`. The file is created by `embr auth login` and can be removed with `embr auth logout`.
- Nothing else. There is no cache of channels, messages or viewers beyond the process lifetime.

## Where data goes

- Twitch's API (`api.twitch.tv`, `id.twitch.tv`, `gql.twitch.tv`, `usher.ttvnw.net`) receives the
  requests you make and your OAuth token.
- If you configure a refresh endpoint with `embr config set-refresh-url` or `EMBR_REFRESH_URL` (for
  example, using Embr's client id), token refresh goes through that endpoint over TLS and carries your
  refresh token; Embr's worker does not store it. Use your own Twitch application (recommended) or set
  `EMBR_DISABLE_WORKER_REFRESH=1` to keep refresh local.
- `chat history` calls `recent-messages.robotty.de`.
- `emotes 7tv`, `emotes bttv` and `emotes ffz` call those providers' public APIs.
- No other server is contacted.

## Credentials

`--token` and `--client-id` are visible to other local processes through the process list and shell
history. Prefer `EMBR_ACCESS_TOKEN`/`EMBR_CLIENT_ID` or `embr auth login`. `embr auth app-token` prints
a secret by design; do not log its output.
