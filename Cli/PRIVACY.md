# Privacy

`embr` runs on your machine. It has no analytics, telemetry, crash reporting or advertising.

## What it stores

- Twitch access and refresh tokens in `${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json`, mode
  `0600`. The file is created by `embr auth login` and can be removed with `embr auth logout`.
- Nothing else. There is no cache of channels, messages or viewers beyond the process lifetime.

## Where data goes

- Twitch's API (`api.twitch.tv`, `id.twitch.tv`, `gql.twitch.tv`, `usher.ttvnw.net`) receives the
  requests you make and your OAuth token.
- If you sign in with Embr's client id, token refresh goes through Embr's worker
  (`embr.guitaripod.workers.dev/auth/refresh`), which holds the app secret. That request carries your
  refresh token over TLS; the worker does not store it. Use your own Twitch application (recommended),
  set `EMBR_REFRESH_URL`, or set `EMBR_DISABLE_WORKER_REFRESH=1` to keep refresh local.
- `chat history` calls `recent-messages.robotty.de`.
- `emotes 7tv`, `emotes bttv` and `emotes ffz` call those providers' public APIs.
- No other server is contacted.

## Credentials

`--token` and `--client-id` are visible to other local processes through the process list and shell
history. Prefer `EMBR_ACCESS_TOKEN`/`EMBR_CLIENT_ID` or `embr auth login`. `embr auth app-token` prints
a secret by design; do not log its output.
