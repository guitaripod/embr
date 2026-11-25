---
name: embr-cli
description: Drive Twitch from the terminal with the embr CLI — browse streams, read and send chat, moderate, run Studio actions (ads, polls, predictions, goals, Shield Mode), stream EventSub/IRC as NDJSON, fetch emotes and resolve playback URLs. Use when a task needs live Twitch data or actions and `embr` is installed.
---

# embr CLI

`embr` is the agent-native Twitch CLI built on EmbrCore. One binary, JSON everywhere, no prompts.

## Before anything

```sh
embr doctor --json          # binary, config, token, optional network
embr commands --json        # full catalog: names, args, options, scopes, examples
```

Auth precedence: `--client-id`/`--token` flags → `EMBR_CLIENT_ID`/`EMBR_ACCESS_TOKEN` (or
`TWITCH_*`) → `~/.config/embr/credentials.json`. If the token is missing or expired, ask the human to
run `embr auth login` (it needs their browser/phone). `auth login --no-wait --json` plus `auth poll`
lets an agent drive the device flow. Embr's client id refreshes through Embr's worker; another
confidential app needs `EMBR_CLIENT_SECRET` (the error hint says so when it is missing).

## Output contract

- stdout: data only. Piped output defaults to `{"ok":true,"command":"…","data":…,"meta":…}`.
- stderr: JSON error envelopes `{"ok":false,"error":{"kind","status","message","hint"}}`.
- Exit codes: 0 ok, 2 usage, 3 auth/scope, 4 not found, 5 rate limited, 6 network, 7 server,
  8 decode.
- `--json`, `--ndjson`, `--table`, `--raw` (Twitch payload, first page), `--all`, `--first`,
  `--after`, `--max-pages`, `--timeout`, `--retries`, `--profile`, `--no-input`, `--quiet`,
  `--verbose`. `--version --json` returns `{"name","version"}`.

## Read

```sh
embr streams top --first 10 --json
embr streams get xqc shroud --json
embr channels info xqc --json
embr chat chatters xqc --all --json
embr chat emotes user --all --json
embr mod banned xqc --all --json
embr schedule get xqc --json
```

Results are camelCase models. Use `--raw` when you need Twitch's exact fields.

## Mutate

Always dry-run first, then send. Pass numeric ids when you know them so the dry run shows the real
request instead of a login lookup.

```sh
embr chat send xqc "hello" --dry-run --json
embr chat send xqc "hello" --json
embr mod ban xqc 123456 --reason spam --duration 600 --json
embr chat pin xqc <message-id> --duration 600 --json
embr channels edit xqc --title "Late night" --game-id 509658 --json
embr studio ad-start xqc --length 60 --json
```

Moderation commands take `--as <moderator>` when the token user is not the moderator. Mutating
commands are listed with `"mutating": true` in the catalog.

## Stream

```sh
embr chat watch xqc --anonymous --limit 50 --ndjson
embr chat watch xqc --limit 50            # EventSub when signed in
embr eventsub listen --chat xqc --limit 20
embr eventsub listen --duration 60
```

Each line is a JSON object with `type` (`message`, `notification`, `keepalive`, `reconnect`,
`roomstate`, `delete`, `clear`, `notice`). Messages carry the text in `message` and transport detail in
`data`; EventSub messages keep the raw Twitch event under `data`. `--limit` counts messages, not
keepalives. Stop with `--limit`/`--duration`; reconnects are automatic and created subscriptions are
deleted on exit.

## Other

```sh
embr chat history xqc --limit 50 --json          # no token needed
embr playback url xqc --json                     # live HLS URL
embr playback url --vod 1234567890 --json
embr emotes all xqc --json                       # provider ids: twitch, 7tv, bttv, ffz
embr auth app-token --json                       # secret: never log it
```

`--raw` on streaming commands includes unparsed IRC lines. `embr help exclusions` lists what the CLI
does not cover (worker backend, StoreKit, favorites, player).
