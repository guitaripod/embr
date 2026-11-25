# Security

## Reporting

Use GitHub's private vulnerability reporting on this repository, or email security@midgarcorp.cc.
Do not open a public issue with a token, refresh token, client secret or a working exploit.

## Supported versions

The latest release and the current `master`.

## Token handling

- Tokens live in `${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json` with mode `0600`.
- `embr auth status` and `embr config show` never print tokens.
- `embr auth app-token` is the only command that prints a secret, and it exists for that purpose.
- `--token` on the command line is visible in the process list; prefer `EMBR_ACCESS_TOKEN`.
- `--dry-run` redacts authorization headers, token-bearing query parameters and secret fields in
  request bodies.
- Refresh through Embr's worker sends the refresh token over TLS; it is not stored there. Use your own
  Twitch application or `EMBR_DISABLE_WORKER_REFRESH=1` to refresh locally.
