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

Both install `~/.local/bin/embr`. Verify with `embr doctor`.

## Sign in

Create a Twitch application in the developer console (public client, no secret), then:

```sh
embr auth login --client-id <client-id>
```

The device flow prints a code and a `twitch.tv/activate` link. Tokens are stored at
`${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json`, mode `0600`, under a profile (`--profile`,
default `default`). `--scopes` takes presets (`chat`, `mod`, `studio`, `channel`, `user`, `all`) or
explicit scopes. For unattended agents, `embr auth login --no-wait --json` and `embr auth poll`.

Environment variables override the file: `EMBR_CLIENT_ID` (or `TWITCH_CLIENT_ID`),
`EMBR_ACCESS_TOKEN` (or `TWITCH_ACCESS_TOKEN`), `EMBR_REFRESH_TOKEN`, `EMBR_CLIENT_SECRET` (only for
`auth app-token`).

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
session. Both emit NDJSON, follow Twitch's reconnect URL, and stop on `--limit` or `--duration`.

## Agent use

- Discover with `embr commands --json`; do not scrape help.
- Parse the `ok`/`data`/`error` envelope; check the exit code.
- Mutations: inspect with `--dry-run` first. Pass numeric ids to see the final request instead of a
  user lookup.
- Streams: read NDJSON line by line, stop with `--limit` or `--duration`.
- Never log `auth app-token` output; every other command keeps secrets out of stdout.

See `SKILL.md` for recipes.

## Notes

- Built on EmbrCore; transport and help are the CLI's own.
- WebSocket support comes from `websocket-kit` (NIO); everything else is Foundation.
- Not exposed: Embr's worker/account backend, StoreKit, favorites/alerts/watch history, the player and
  HLS ad stripping. `embr help exclusions` explains why.
- GPL-3.0, like the rest of the monorepo.
