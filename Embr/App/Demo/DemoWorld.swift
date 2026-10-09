#if DEBUG
import Foundation
import EmbrCore

struct DemoGame: Sendable {
    let id: String
    let name: String
    let motif: DemoMotif
    let palette: DemoPalette
}

struct DemoChannel: Sendable {
    let id: String
    let login: String
    let name: String
    let gameID: String
    let title: String
    let viewers: Int
    let minutesLive: Int
    let language: String
    let tags: [String]
    let bio: String
    let partner: String
    let yearsOld: Int

    var isLive: Bool { viewers > 0 }
}

/// A fictional, fully offline stand-in for the live service, used by DEBUG screenshot captures:
/// invented channels, categories and chat, with every request answered locally.
enum DemoWorld {
    static let host = "demo.embr"
    static let userID = "90001"
    static let userLogin = "emberfan"

    static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["EMBR_DEMO"] == "1" || ProcessInfo.processInfo.arguments.contains("-embrDemo")
    }()

    /// A demo launch starts from nothing: whatever an earlier launch stored in the app's defaults is
    /// gone before any store reads it, so relaunching always lands on the same screen.
    static func resetLaunchState() {
        guard isActive, let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    static func game(id: String) -> DemoGame? {
        games.first { $0.id == id }
    }

    static func channel(login: String) -> DemoChannel? {
        let lowered = login.lowercased()
        return channels.first { $0.login == lowered }
    }

    static func channel(id: String) -> DemoChannel? {
        channels.first { $0.id == id }
    }

    static var liveChannels: [DemoChannel] {
        channels.filter(\.isLive).sorted { $0.viewers > $1.viewers }
    }

    static let followedLogins = [
        "lumenfox", "northerncrane", "quietmoth", "kitsunetea", "halcyonbyte", "mossandmirrors",
        "orbitalnora", "copperlark", "sleepylighthousekeeper", "saltmarsh", "paperlantern", "glimmerlane",
        "marigoldfm", "anviljoe", "fernwhistle", "coldbrewcarl", "tuftedtitmouse", "lowtidelou"
    ]

    static let favoriteLogins = [
        "pixelpilgrim", "quietmoth", "velvetkraken", "copperlark", "tinkerwick", "bramblejack",
        "crimsoncarto", "thunderpanda", "cobaltcove", "marigoldfm", "anviljoe", "fernwhistle"
    ]

    static let recentLogins = [
        "lumenfox", "kitsunetea", "mossandmirrors", "rookery", "orbitalnora", "tinkerwick", "driftwooddan", "nightjar"
    ]

    private static func palette(_ sky: UInt32, _ horizon: UInt32, _ ground: UInt32, _ accent: UInt32) -> DemoPalette {
        DemoPalette(sky: sky, horizon: horizon, ground: ground, accent: accent)
    }

    static let games: [DemoGame] = [
        DemoGame(id: "9101", name: "Hollow Circuit", motif: .arena, palette: palette(0x0b1030, 0x1b1f5e, 0x2a0f4a, 0x2ee6d6)),
        DemoGame(id: "9102", name: "Tidebreaker Tactics", motif: .arena, palette: palette(0x06303a, 0x0b5560, 0x0a2230, 0xffb454)),
        DemoGame(id: "9103", name: "Starfall Frontier", motif: .space, palette: palette(0x050818, 0x1a1646, 0x6d3fd1, 0xff7ac6)),
        DemoGame(id: "9104", name: "Cozy Hollow", motif: .farm, palette: palette(0x8fd3f4, 0xfbe3b0, 0x5da75a, 0xd9573f)),
        DemoGame(id: "9105", name: "Rift Arena", motif: .arena, palette: palette(0x1a0a0a, 0x4a1410, 0x2b0c0c, 0xff6a3d)),
        DemoGame(id: "9106", name: "Gambit Club", motif: .board, palette: palette(0x1d2b2a, 0x34504a, 0xc9b27c, 0x7bdcb5)),
        DemoGame(id: "9107", name: "Open Road Rally", motif: .road, palette: palette(0xf6a65a, 0xf9d08b, 0x2f4a35, 0xff4d4d)),
        DemoGame(id: "9108", name: "Pixel Depths", motif: .dungeon, palette: palette(0x1b1426, 0x2c2140, 0x3a3050, 0xffc857)),
        DemoGame(id: "9109", name: "Talk & Hangout", motif: .room, palette: palette(0x3a1f4d, 0x7a3d6b, 0x2a1530, 0xffb86b)),
        DemoGame(id: "9110", name: "Studio Sessions", motif: .studio, palette: palette(0x140a24, 0x2a1450, 0x1a0c30, 0xb06bff)),
        DemoGame(id: "9111", name: "Art Atelier", motif: .canvas, palette: palette(0xf4a6c0, 0xf8d9a0, 0x6fb8d6, 0xe8506f)),
        DemoGame(id: "9112", name: "Speedrun Lab", motif: .dungeon, palette: palette(0x0c1a2e, 0x16304f, 0x20476b, 0x6bd6ff)),
        DemoGame(id: "9113", name: "Mech Foundry", motif: .arena, palette: palette(0x15181d, 0x2b3139, 0x3a424c, 0xffd23f)),
        DemoGame(id: "9114", name: "Skyward Craft", motif: .peaks, palette: palette(0x7ec8ff, 0xcfeaff, 0x3f8d4a, 0xffe27a)),
        DemoGame(id: "9115", name: "Quiz Night", motif: .room, palette: palette(0x0f2a4a, 0x1d4d80, 0x0b1c33, 0xffdd55)),
        DemoGame(id: "9116", name: "Retro Reloaded", motif: .dungeon, palette: palette(0x2a0f1f, 0x4a1a35, 0x5a2a45, 0xff5fa2)),
        DemoGame(id: "9117", name: "Night Radio", motif: .studio, palette: palette(0x0a0f24, 0x14214a, 0x0b1230, 0x5aa9ff)),
        DemoGame(id: "9118", name: "Kitchen Table", motif: .room, palette: palette(0x5a2d1a, 0xa8602d, 0x3a1d10, 0xffcf70)),
        DemoGame(id: "9119", name: "Wild Trails", motif: .peaks, palette: palette(0xffb36b, 0xffe2b0, 0x2f5d3a, 0xfff2a8)),
        DemoGame(id: "9120", name: "Frost Kingdoms", motif: .peaks, palette: palette(0x9fc9e8, 0xe6f2fb, 0x5b7fa6, 0xffffff)),
        DemoGame(id: "9121", name: "Courier Dash", motif: .road, palette: palette(0x24124a, 0xa23c8f, 0x1a0f33, 0x4df0ff)),
        DemoGame(id: "9122", name: "Echoes of Lumen", motif: .peaks, palette: palette(0x2b1a5a, 0xc05fa0, 0x3a2470, 0xffd9a0)),
        DemoGame(id: "9123", name: "Lantern Quest", motif: .farm, palette: palette(0x10223a, 0x2c4a6a, 0x1f3a2e, 0xffb347)),
        DemoGame(id: "9124", name: "Pitch Manager", motif: .board, palette: palette(0x0f3320, 0x1f5a35, 0x2f8a4d, 0xe6ff7a))
    ]

    static let channels: [DemoChannel] = [
        DemoChannel(id: "71001", login: "lumenfox", name: "LumenFox", gameID: "9101", title: "Glass Foundry, no-hit attempt #14: chat picks the loadout", viewers: 41230, minutesLive: 214, language: "en", tags: ["English", "Roguelike", "NoHit"], bio: "No-hit runs, loadout roulette and the occasional victory lap. Streaming five nights a week.", partner: "partner", yearsOld: 6),
        DemoChannel(id: "71002", login: "pixelpilgrim", name: "PixelPilgrim", gameID: "9108", title: "Floor 40 or bust • hardcore, one life", viewers: 28740, minutesLive: 97, language: "en", tags: ["English", "Hardcore", "Dungeon"], bio: "One life, one dungeon, zero regrets. Hardcore runs every evening.", partner: "partner", yearsOld: 4),
        DemoChannel(id: "71003", login: "northerncrane", name: "NorthernCrane", gameID: "9102", title: "Ranked ladder climb with commentary", viewers: 19620, minutesLive: 301, language: "en", tags: ["English", "Strategy", "Ranked"], bio: "Climbing the ladder and explaining every decision along the way.", partner: "partner", yearsOld: 5),
        DemoChannel(id: "71004", login: "quietmoth", name: "QuietMoth", gameID: "9104", title: "Rainy morning on the farm ☕ planting the whole south field", viewers: 15310, minutesLive: 58, language: "en", tags: ["English", "Cozy", "Relaxing"], bio: "Slow mornings, soft music and a very large turnip field.", partner: "partner", yearsOld: 3),
        DemoChannel(id: "71005", login: "kitsunetea", name: "KitsuneTea", gameID: "9109", title: "ゆったり雑談 ☕ 今日あったことを話します", viewers: 12480, minutesLive: 143, language: "ja", tags: ["日本語", "雑談", "まったり"], bio: "夜のゆるい雑談配信です。お茶を片手に、のんびりどうぞ。", partner: "partner", yearsOld: 4),
        DemoChannel(id: "71006", login: "velvetkraken", name: "VelvetKraken", gameID: "9105", title: "Grandmaster lobby, aim routines first 🎯", viewers: 11870, minutesLive: 176, language: "en", tags: ["English", "Competitive", "Aim"], bio: "Aim routines, scrims and honest reviews of my own mistakes.", partner: "partner", yearsOld: 5),
        DemoChannel(id: "71007", login: "halcyonbyte", name: "HalcyonByte", gameID: "9103", title: "Building a trade empire from one tiny freighter", viewers: 9340, minutesLive: 410, language: "en", tags: ["English", "Space", "Economy"], bio: "Spreadsheets, freighters and the long game.", partner: "partner", yearsOld: 7),
        DemoChannel(id: "71008", login: "mossandmirrors", name: "MossAndMirrors", gameID: "9111", title: "Painting a lighthouse in gouache, requests welcome", viewers: 7120, minutesLive: 66, language: "en", tags: ["English", "Painting", "Chill"], bio: "Gouache, ink and the occasional happy accident.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71009", login: "rookery", name: "Rookery", gameID: "9106", title: "Blitz arena, then analysing your games", viewers: 6580, minutesLive: 122, language: "en", tags: ["English", "Chess", "Educational"], bio: "Blitz, endgames and friendly game reviews.", partner: "partner", yearsOld: 5),
        DemoChannel(id: "71010", login: "orbitalnora", name: "OrbitalNora", gameID: "9112", title: "Any% practice, new route through the Cistern", viewers: 5950, minutesLive: 235, language: "en", tags: ["English", "Speedrun", "Practice"], bio: "Shaving frames off a route nobody asked for.", partner: "partner", yearsOld: 4),
        DemoChannel(id: "71011", login: "copperlark", name: "CopperLark", gameID: "9110", title: "Live looping, writing a track from scratch", viewers: 5210, minutesLive: 88, language: "en", tags: ["English", "Music", "Original"], bio: "Looping pedals, synths and one very patient cat.", partner: "partner", yearsOld: 3),
        DemoChannel(id: "71012", login: "tinkerwick", name: "TinkerWick", gameID: "9113", title: "Neuer Chassis-Bau, wir testen den Prototyp", viewers: 4730, minutesLive: 190, language: "de", tags: ["Deutsch", "Bauen", "Technik"], bio: "Wir bauen Maschinen, die niemand braucht, aber alle wollen.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71013", login: "sleepylighthousekeeper", name: "SleepyLighthouseKeeper", gameID: "9117", title: "Late shift: lo-fi, letters from listeners, tea", viewers: 4390, minutesLive: 312, language: "en", tags: ["English", "Lo-fi", "Cozy"], bio: "Keeping the light on and reading your letters out loud.", partner: "partner", yearsOld: 2),
        DemoChannel(id: "71014", login: "bramblejack", name: "BrambleJack", gameID: "9114", title: "Day 100: the floating village finally has a harbour", viewers: 3980, minutesLive: 51, language: "en", tags: ["English", "Building", "Survival"], bio: "A hundred days, one floating village.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71015", login: "saltmarsh", name: "Saltmarsh", gameID: "9119", title: "Trilha ao nascer do sol, ao vivo da serra", viewers: 3560, minutesLive: 167, language: "pt", tags: ["Português", "Outdoors", "Aventura"], bio: "Trilhas, nascer do sol e muito café.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71016", login: "crimsoncarto", name: "CrimsonCarto", gameID: "9120", title: "Campaign finale: holding the northern pass", viewers: 3120, minutesLive: 244, language: "en", tags: ["English", "Strategy", "Campaign"], bio: "Long campaigns, longer maps.", partner: "partner", yearsOld: 4),
        DemoChannel(id: "71017", login: "paperlantern", name: "PaperLantern", gameID: "9118", title: "Cocinando paella para doce, ¡pregunten lo que quieran!", viewers: 2840, minutesLive: 39, language: "es", tags: ["Español", "Cocina", "Charla"], bio: "Recetas de casa y charla de sobremesa.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71018", login: "thunderpanda", name: "ThunderPanda", gameID: "9121", title: "Arcade high score marathon, 1M points or bust", viewers: 2410, minutesLive: 120, language: "en", tags: ["English", "Arcade", "Marathon"], bio: "Chasing one million points, one coin at a time.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71019", login: "glimmerlane", name: "GlimmerLane", gameID: "9122", title: "Chapter 7 blind playthrough, no spoilers please", viewers: 2160, minutesLive: 275, language: "en", tags: ["English", "RPG", "Blind"], bio: "Blind playthroughs and a strict no-spoilers policy.", partner: "partner", yearsOld: 4),
        DemoChannel(id: "71020", login: "cobaltcove", name: "CobaltCove", gameID: "9116", title: "Beating every cartridge on the shelf, week 3", viewers: 1870, minutesLive: 330, language: "en", tags: ["English", "Retro", "Marathon"], bio: "A shelf of old cartridges and a plan.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71021", login: "wildernessjo", name: "WildernessJo", gameID: "9107", title: "Dirt stage championship, round 4", viewers: 1520, minutesLive: 74, language: "en", tags: ["English", "Racing", "Championship"], bio: "Mud, gravel and photo finishes.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71022", login: "driftwooddan", name: "DriftwoodDan", gameID: "9123", title: "Cosy puzzler, lighting all the lamps", viewers: 1180, minutesLive: 150, language: "en", tags: ["English", "Puzzle", "Cozy"], bio: "Small puzzles for slow evenings.", partner: "", yearsOld: 1),
        DemoChannel(id: "71023", login: "nightjar", name: "Nightjar", gameID: "9115", title: "Quiz du soir : culture générale, venez jouer !", viewers: 940, minutesLive: 62, language: "fr", tags: ["Français", "Quiz", "Communauté"], bio: "Le quiz du soir, ouvert à tous.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71024", login: "hexagonhalo", name: "HexagonHalo", gameID: "9124", title: "Season 3: promotion push with a 4-3-3", viewers: 720, minutesLive: 205, language: "en", tags: ["English", "Management", "Football"], bio: "Spreadsheets with a football problem.", partner: "", yearsOld: 1),
        DemoChannel(id: "71025", login: "sablesong", name: "SableSong", gameID: "9110", title: "Piano improv and requests", viewers: 540, minutesLive: 31, language: "en", tags: ["English", "Piano", "Requests"], bio: "Piano, requests and good company.", partner: "", yearsOld: 1),
        DemoChannel(id: "71026", login: "emberwren", name: "EmberWren", gameID: "9101", title: "Chill co-op with the community, join up!", viewers: 410, minutesLive: 480, language: "en", tags: ["English", "Co-op", "Community"], bio: "Co-op nights open to everyone.", partner: "", yearsOld: 1),
        DemoChannel(id: "71027", login: "tidalpine", name: "TidalPine", gameID: "9104", title: "First week on the farm, please be gentle", viewers: 255, minutesLive: 26, language: "en", tags: ["English", "Cozy", "Beginner"], bio: "Brand new to farming and loving it.", partner: "", yearsOld: 1),
        DemoChannel(id: "71028", login: "gulliverbright", name: "GulliverBright", gameID: "9109", title: "Unpacking the new desk setup", viewers: 188, minutesLive: 47, language: "en", tags: ["English", "Setup", "Chat"], bio: "Desks, cables and conversation.", partner: "", yearsOld: 1),
        DemoChannel(id: "71029", login: "wrenandrye", name: "WrenAndRye", gameID: "9111", title: "Sketchbook night: faces and hands", viewers: 121, minutesLive: 19, language: "en", tags: ["English", "Sketching", "Chill"], bio: "Sketchbooks and warm tea.", partner: "", yearsOld: 1),
        DemoChannel(id: "71030", login: "owlmanor", name: "OwlManor", gameID: "9103", title: "Salvage run through the asteroid belt", viewers: 112, minutesLive: 12, language: "en", tags: ["English", "Space", "Salvage"], bio: "Salvage runs and bad decisions.", partner: "", yearsOld: 1),
        DemoChannel(id: "71031", login: "marigoldfm", name: "MarigoldFM", gameID: "9117", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Radio"], bio: "Weekend radio from a very small garden shed.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71032", login: "anviljoe", name: "AnvilJoe", gameID: "9113", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Building"], bio: "Forge, anvil and a lot of patience.", partner: "", yearsOld: 2),
        DemoChannel(id: "71033", login: "fernwhistle", name: "FernWhistle", gameID: "9119", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Outdoors"], bio: "Walks, whistles and ferns.", partner: "", yearsOld: 2),
        DemoChannel(id: "71034", login: "coldbrewcarl", name: "ColdBrewCarl", gameID: "9109", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Chat"], bio: "Coffee first, talking second.", partner: "", yearsOld: 2),
        DemoChannel(id: "71035", login: "tuftedtitmouse", name: "TuftedTitmouse", gameID: "9111", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Art"], bio: "Birds, inks and long walks.", partner: "", yearsOld: 1),
        DemoChannel(id: "71037", login: "mosscrown", name: "MossCrown", gameID: "9104", title: "Harvest festival prep, the pumpkins are enormous", viewers: 8130, minutesLive: 73, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 1),
        DemoChannel(id: "71038", login: "teapotterry", name: "TeapotTerry", gameID: "9104", title: "Rebuilding the greenhouse after the storm", viewers: 6240, minutesLive: 112, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71039", login: "snailmail", name: "SnailMail", gameID: "9104", title: "Reading your letters while the soup simmers", viewers: 5480, minutesLive: 44, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71040", login: "bettysbees", name: "BettysBees", gameID: "9104", title: "Day 3 of the great beehive experiment", viewers: 4310, minutesLive: 95, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 4),
        DemoChannel(id: "71041", login: "lanternlily", name: "LanternLily", gameID: "9104", title: "Late harvest by lantern light, slow and quiet", viewers: 3720, minutesLive: 201, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 1),
        DemoChannel(id: "71042", login: "puddlejump", name: "PuddleJump", gameID: "9104", title: "Morning chores with the rain on the roof", viewers: 2960, minutesLive: 36, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 2),
        DemoChannel(id: "71043", login: "kettleandcrow", name: "KettleAndCrow", gameID: "9104", title: "Baking day: bread, pies and one suspicious cake", viewers: 2290, minutesLive: 128, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "affiliate", yearsOld: 3),
        DemoChannel(id: "71044", login: "oatmealowl", name: "OatmealOwl", gameID: "9104", title: "Sunday farm tour, new animals incoming", viewers: 1710, minutesLive: 83, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "", yearsOld: 4),
        DemoChannel(id: "71045", login: "dewdropdani", name: "DewdropDani", gameID: "9104", title: "Decorating the barn for autumn", viewers: 1240, minutesLive: 57, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "", yearsOld: 1),
        DemoChannel(id: "71046", login: "foxglovefarm", name: "FoxgloveFarm", gameID: "9104", title: "Learning to fish at the old pond, no rush", viewers: 830, minutesLive: 166, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "", yearsOld: 2),
        DemoChannel(id: "71047", login: "ramblingrye", name: "RamblingRye", gameID: "9104", title: "Trading stories and seeds in the market square", viewers: 460, minutesLive: 29, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "", yearsOld: 3),
        DemoChannel(id: "71048", login: "sproutandsun", name: "SproutAndSun", gameID: "9104", title: "First harvest ever, wish me luck", viewers: 190, minutesLive: 18, language: "en", tags: ["English", "Cozy", "Farming"], bio: "Slow streams, soft music and a lot of vegetables.", partner: "", yearsOld: 4),
        DemoChannel(id: "71036", login: "lowtidelou", name: "LowTideLou", gameID: "9114", title: "", viewers: 0, minutesLive: 0, language: "en", tags: ["English", "Building"], bio: "Builds that only exist at low tide.", partner: "", yearsOld: 1),
    ]

    static let emoteNames = ["pogfox", "heartbeat", "clapfox", "sadmoth", "owlwave", "noodlelove", "gg", "hypefox", "o7", "cozycup", "kekw2", "popcornpanda"]

    static func startedAt(of channel: DemoChannel) -> Date {
        Date().addingTimeInterval(-TimeInterval(channel.minutesLive * 60))
    }

    static func thumbnailTemplate(login: String) -> String {
        "https://\(host)/thumb/\(login)/{width}x{height}"
    }

    static func boxArtTemplate(gameID: String) -> String {
        "https://\(host)/box/\(gameID)/{width}x{height}"
    }

    static func avatarURL(login: String) -> String {
        "https://\(host)/avatar/\(login)"
    }
}
#endif
