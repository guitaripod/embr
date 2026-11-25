import Foundation

enum HelpTopics {
    static func text(_ topic: String) -> String? {
        switch topic {
        case "auth": return auth
        case "output": return output
        case "scopes": return scopes
        case "agents": return agents
        case "exit-codes": return exitCodes
        case "exclusions": return exclusions
        default: return nil
        }
    }

    private static let auth = """
    embr auth — sign-in, refresh and tokens

    `embr auth login` runs Twitch's device code grant: it prints a code and a twitch.tv/activate link,
    then waits (up to 15 minutes) until you approve it. Tokens are stored in
    ${XDG_CONFIG_HOME:-~/.config}/embr/credentials.json with mode 0600, in the profile named by
    --profile (default: default).

    For unattended agents, split it in two:
      embr auth login --no-wait --json          # prints deviceCode, userCode, verificationURI
      embr auth poll --device-code <code>       # poll once; repeat until it returns authorized

    Precedence for every command: flags (--client-id, --token), then environment
    (EMBR_CLIENT_ID/TWITCH_CLIENT_ID, EMBR_ACCESS_TOKEN/TWITCH_ACCESS_TOKEN, EMBR_REFRESH_TOKEN),
    then the config file.

    Tokens refresh automatically 60 seconds before expiry. A refresh rewrites the config file. A
    confidential Twitch app needs EMBR_CLIENT_SECRET for that refresh; without it, sign in again.
    `embr auth app-token` is the only command that prints a secret; it reads the client secret from
    --client-secret-env or stdin, never from argv.

    Scope presets for login: chat, mod, studio, channel, user, all (default). `embr help scopes`
    lists what each gives you.
    """

    private static let output = """
    embr — output contract

    On a terminal the default is a table for list commands and pretty JSON otherwise. When stdout is
    a pipe the default is the JSON envelope. Override with --json, --table or --ndjson.

    Success envelope:
      {"ok":true,"command":"streams.top","data":[…],"pagination":{"cursor":"…"},"meta":{"count":20,"total":42}}

    Errors go to stderr and use the same envelope with ok:false:
      {"ok":false,"command":"chat.send","error":{"kind":"auth","message":"…","status":401,"hint":"…"}}

    --raw prints Twitch's payload instead of the CLI's camelCase shape.
    --ndjson prints one object per line; listing commands stream items, and `chat watch` /
    `eventsub listen` stream events as they arrive.

    Mutating commands accept --dry-run, which prints the method, URL, headers (secrets redacted) and
    body without sending anything.
    """

    private static let scopes = """
    embr — scopes

    chat       chat:read chat:edit user:read:chat user:write:chat
    mod        moderator:read:chatters moderator:manage:banned_users moderator:manage:chat_messages
               moderator:read:chat_messages moderator:manage:chat_settings moderator:manage:automod
               moderator:manage:unban_requests moderator:manage:shoutouts moderator:manage:shield_mode
               moderator:read:shield_mode moderator:read:followers moderation:read user:read:moderated_channels
    studio     channel:read:ads channel:manage:ads channel:edit:commercial channel:read:polls
               channel:read:predictions channel:read:hype_train channel:read:goals channel:read:redemptions
               bits:read channel:read:subscriptions
    channel    channel:manage:broadcast channel:read:vips channel:manage:vips
    user       user:read:emotes user:read:follows user:read:blocked_users user:manage:blocked_users
    all        every scope above

    Some endpoints also accept an app token; the CLI uses the token you give it as-is and prints the
    missing scope when Twitch refuses a call.
    """

    private static let agents = """
    embr — agent contract

    Discover:      embr commands --json            # full catalog, no scraping
                   embr <group> --help
    Read:          embr streams top --json --first 5
                   embr chat chatters <channel> --json --all
    Mutate:        embr chat send <channel> "hi" --json --dry-run
                   embr mod ban <channel> <user> --reason spam --json
    Stream:        embr chat watch <channel> --ndjson --limit 100
                   embr eventsub listen --chat <channel> --ndjson
    Diagnose:      embr doctor --json
    Errors:        exit code + JSON on stderr; stdout only ever carries data.
    Tokens:        never printed by read/mutate commands; `auth app-token` is the explicit exception.
    Prompts:       none. `auth login --no-wait` exists for scripted sign-in.
    Pagination:    --all follows cursors (capped by --max-pages, default 50); --after starts anywhere.
    Rate limits:   the CLI retries idempotent calls and sleeps until the reset when the budget is gone.
    """

    private static let exitCodes = """
    embr — exit codes

    0    success
    2    usage error
    3    missing, expired or under-scoped token
    4    user, channel, message or subscription not found
    5    rate limited after retries
    6    network failure
    7    Twitch server error
    8    response could not be decoded
    130  interrupted
    """

    private static let exclusions = """
    embr — what the CLI deliberately leaves out

    The CLI covers EmbrCore's Twitch surface. These Embr features are app-only and have no command:

    - Embr's Cloudflare worker: login exchange, playback proxy, reports, supporter data. It is
      Embr's account backend and needs Embr's own secrets; use `auth` and `playback` instead.
    - StoreKit purchases, supporter badges and Founding Member state.
    - Favorites, watch history, alerts, session tally and multiview layout: local app state.
    - Video playback and HLS ad stripping. `playback url` prints Usher URLs; the player is the app.
    - Chat highlighting, filters and spam detection: rendering logic, not data.

    Anything Twitch offers that EmbrCore does not model (raids, markers, bits leaderboard, channel
    points rewards, schedules editing, whispers) is also out; add it to EmbrCore first.
    """
}
