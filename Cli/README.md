# embr CLI

Twitch from the terminal, built on EmbrCore. It covers everything Embr's core can do that fits a CLI: reading streams, channels, chat and schedules; sending and moderating chat; Studio tools such as ads, polls, predictions, goals and Shield Mode; EventSub and anonymous IRC streaming; Twitch, 7TV, BetterTTV and FrankerFaceZ emotes; and resolving live or VOD playback URLs.

## Install

macOS:

```sh
cd apps/embr/Cli
./scripts/install.sh
```

Linux (Arch, Debian, Ubuntu): the script uses a local Swift toolchain if present, otherwise the `swift:6.4.1-jammy` Docker image with a statically linked Swift runtime.

```sh
cd apps/embr/Cli
./scripts/install.sh
```

Both install `~/.local/bin/embr` (override with `EMBR_BIN_DIR`). Verify with `embr doctor`.

Shell completion:

```sh
embr completion bash > ~/.bash_completion.d/embr
embr completion zsh  > ~/.zsh/completions/_embr
embr completion fish > ~/.config/fish/completions/embr.fish
```

## Sign in

Create a Twitch application in the developer console (public client, no secret), then:

```sh
embr auth login --client-id <client-id>
```

The device flow prints a code and a `twitch.tv/activate` link. Tokens are stored at
`${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json`, mode `0600`, under a profile (`--profile`,
default `default`). `--scopes` takes presets (`chat`, `mod`, `studio`, `channel`, `user`, `all`) or
explicit scopes. For unattended agents, `embr auth login --no-wait --json` and `embr auth poll`.

A confidential Twitch app (including Embr's existing client id) needs `EMBR_CLIENT_SECRET` to refresh
tokens; without it, `auth refresh` fails and you sign in again when the access token expires. A public
client refreshes with the client id alone.

Environment variables override the file: `EMBR_CLIENT_ID` (or `TWITCH_CLIENT_ID`),
`EMBR_ACCESS_TOKEN` (or `TWITCH_ACCESS_TOKEN`), `EMBR_REFRESH_TOKEN`, `EMBR_CLIENT_SECRET` (for
`auth app-token`, and for refreshing tokens when the Twitch app is confidential).

## Quick start

```sh
embr streams top --first 10
embr channels info xqc
embr chat chatters xqc --all
embr chat send xqc "hello"
embr mod ban xqc spammer --reason spam --duration 600
embr studio ad-schedule xqc
embr chat watch xqc --anonymous --limit 20
embr playback url xqc
```

`--json` gives a stable envelope on stdout; errors are JSON on stderr with a non-zero exit code.
`--dry-run` prints the HTTP request instead of sending it. `--all` follows cursors; `--first`,
`--after` and `--max-pages` control paging. `--ndjson` streams one object per line.

| Global flag | Meaning |
|---|---|
| `--json` / `--table` / `--ndjson` | Output mode; pipes default to JSON |
| `--raw` | Print Twitch's payload instead of the CLI's model |
| `--all`, `--first N`, `--after C`, `--max-pages N` | Pagination |
| `--dry-run` | Print the request, redacted, and send nothing |
| `--profile NAME` | Credential profile |
| `--client-id` / `--token` | One-shot credential overrides |
| `--timeout S` / `--retries N` | Network tuning |
| `--quiet` / `--verbose` / `--trace` / `--no-color` | Logging and presentation |
| `--no-input` | Never read stdin |
| `--version` / `--help` | Version and help |

Exit codes: `0` ok, `2` usage, `3` auth/scope, `4` not found, `5` rate limited, `6` network, `7`
server, `8` decode, `130` interrupted.

```json
{"ok":true,"command":"streams top","data":[…],"pagination":{"cursor":"…"},"meta":{"count":20}}
{"ok":false,"command":"chat send","error":{"kind":"auth","status":401,"message":"…","hint":"…"}}
```

## Commands

| Group | What it does |
|---|---|
| `auth` | Device login, poll, status, refresh, logout, app token |
| `config` | Credentials path and profiles (never secrets) |
| `streams`, `games`, `search` | Browse live streams, categories, search |
| `users`, `channels` | Lookups, channel edit, followed, followers |
| `videos`, `clips`, `schedule` | VODs, clips, schedules |
| `chat` | Send, settings, emotes, badges, chatters, pins, shoutout, history, watch |
| `mod` | Ban, unban, delete, AutoMod, unban requests, banned/moderators/VIPs |
| `studio` | Ad schedule/start/snooze, Hype Train, poll, prediction, goals, followers, Shield Mode |
| `eventsub` | List/create/delete subscriptions; `listen` streams events |
| `emotes` | Twitch, 7TV, BetterTTV, FrankerFaceZ |
| `playback` | Live or VOD Usher/HLS URL |
| `commands` | The full machine-readable catalog |
| `doctor` | Install, credential, token and network checks |

Run `embr --help`, `embr <group> --help`, or `embr <command> --help`. Conceptual topics:
`embr help auth`, `help output`, `help scopes`, `help agents`, `help exit-codes`, `help exclusions`.

## Streaming

`embr chat watch <channel>` uses EventSub when signed in and anonymous IRC otherwise; force IRC with
`--anonymous`. `embr eventsub listen --chat <channel>` opens a raw EventSub socket and subscribes the
session. Both emit NDJSON, follow Twitch's reconnect URL, and stop on `--limit` (messages, not
keepalives) or `--duration`.

```json
{"type":"message","transport":"eventsub","channel":"xqc","subscription":"channel.chat.message","message":"hello","data":{…}}
{"type":"roomstate","transport":"irc","channel":"xqc","data":{"emote_only":"false","followers_only":"1440"}}
```

`eventsub listen` prints `welcome`, `keepalive`, `notification`, `reconnect` and `revocation` lines
with the raw event under `event`; `--chat` makes it subscribe automatically. Subscriptions created by
`chat watch`/`eventsub listen` are deleted when the command exits.

## Agent use

- Discover with `embr commands --json`; do not scrape help.
- Parse the `ok`/`data`/`error` envelope; check the exit code.
- Mutations: inspect with `--dry-run` first. Pass numeric ids to see the final request instead of a
  user lookup.
- Streams: read NDJSON line by line, stop with `--limit` or `--duration`.
- Never log `auth app-token` output; every other command keeps secrets out of stdout.

See `SKILL.md` for recipes.

## Troubleshooting

- `401` usually means the token expired. Run `embr auth status`, then `embr auth refresh` or sign in
  again; a confidential app needs `EMBR_CLIENT_SECRET` to refresh.
- `403` names a missing scope. Re-run `embr auth login --scopes all` or pass the exact scope.
- A dry run that stops at a user lookup is telling you to pass numeric ids; the response carries a
  `note` field saying so.
- `doctor --network` checks the token and Helix reachability; without it, only local state.
- `429` is retried for idempotent calls; `--all` sleeps until the rate-limit reset.

## Notes

- Built on EmbrCore; transport and help are the CLI's own.
- WebSocket support comes from `websocket-kit` (NIO); everything else is Foundation.
- Not exposed: Embr's worker/account backend, StoreKit, favorites/alerts/watch history, the player and
  HLS ad stripping. `embr help exclusions` explains why.
- GPL-3.0, like the rest of the monorepo.
