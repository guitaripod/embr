import Foundation

public enum HelixDuration {
    /// Parses a Twitch video duration string such as "1h2m3s", "23m45s", or "58s" into total seconds.
    public static func seconds(from raw: String) -> Int {
        var total = 0
        var current = 0
        var sawDigit = false
        for character in raw {
            if let digit = character.wholeNumberValue, character.isNumber {
                current = current * 10 + digit
                sawDigit = true
            } else {
                switch character {
                case "h", "H": total += current * 3600
                case "m", "M": total += current * 60
                case "s", "S": total += current
                default: break
                }
                current = 0
                sawDigit = false
            }
        }
        if sawDigit { total += current }
        return total
    }
}
