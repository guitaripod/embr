import UIKit
import EmbrCore

extension VideoViewController {
    func presentQualityPicker(from sourceView: UIView) {
        let qualities = player.availableQualities
        let sheet = UIAlertController(title: String(localized: "Quality"), message: nil, preferredStyle: .actionSheet)

        sheet.addAction(qualityAction(named: String(localized: "Auto"), quality: autoQuality, isSelected: !isAudioOnly && player.currentQuality == nil))
        for quality in qualities where isOffered(quality) {
            let selected = quality.isAudioOnly ? isAudioOnly : (!isAudioOnly && player.currentQuality == quality)
            let label = quality.isAudioOnly ? String(localized: "Audio Only") : quality.name
            sheet.addAction(qualityAction(named: label, quality: quality, isSelected: selected))
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    /// Auto has its own row, and audio only would leave a TV that has the picture with none, so it is not offered then.
    private func isOffered(_ quality: StreamQuality) -> Bool {
        quality.name.caseInsensitiveCompare("auto") != .orderedSame && !(quality.isAudioOnly && isPlayingExternally)
    }

    private func qualityAction(named name: String, quality: StreamQuality, isSelected: Bool) -> UIAlertAction {
        let action = UIAlertAction(title: name, style: .default) { [weak self] _ in
            guard let self else { return }
            if quality.isAudioOnly {
                self.setAudioOnly(true)
            } else {
                if self.isAudioOnly { self.setAudioOnly(false) }
                self.player.setQuality(quality)
            }
        }
        action.setValue(isSelected, forKey: "checked")
        return action
    }

    private var autoQuality: StreamQuality {
        StreamQuality(name: "Auto", url: URL(string: "embr://auto")!)
    }
}
