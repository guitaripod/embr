import AVKit
import UIKit
import EmbrCore

/// The title, subtitle, description and artwork the system player shows above the transport bar and in its Info tab,
/// and in the Apple TV's Now Playing.
enum TVPlayerMetadata {
    static func items(title: String, subtitle: String, description: String?, artwork: UIImage?) -> [AVMetadataItem] {
        var items = [
            item(.commonIdentifierTitle, value: title as NSString),
            item(.iTunesMetadataTrackSubTitle, value: subtitle as NSString),
        ]
        if let description, !description.isEmpty {
            items.append(item(.commonIdentifierDescription, value: description as NSString))
        }
        if let data = artwork?.jpegData(compressionQuality: 0.85) {
            items.append(item(.commonIdentifierArtwork, value: data as NSData, dataType: kCMMetadataBaseDataType_JPEG as String))
        }
        return items
    }

    static func live(_ stream: LiveStream, artwork: UIImage?) -> [AVMetadataItem] {
        let channel = stream.userName.isEmpty ? stream.userLogin : stream.userName
        let subtitle = [channel, stream.gameName].filter { !$0.isEmpty }.joined(separator: " · ")
        return items(title: stream.title.isEmpty ? channel : stream.title, subtitle: subtitle, description: nil, artwork: artwork)
    }

    private static func item(_ identifier: AVMetadataIdentifier, value: any NSCopying & NSObjectProtocol, dataType: String? = nil) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        if let dataType { item.dataType = dataType }
        return item.copy() as? AVMetadataItem ?? item
    }
}
