import Foundation

enum Constants {
    static let appName = "Local STT"
    static let maxRecordingDuration: TimeInterval = 120 // seconds
    static let resultAutoHideDuration: TimeInterval = 30 // seconds
    static let copyConfirmationDuration: TimeInterval = 1.5 // seconds
    static let popoverWidth: CGFloat = 340
    static let popoverMinHeight: CGFloat = 80
    static let popoverMaxHeight: CGFloat = 400
    static let autoPasteEnabledKey = "autoPasteEnabled"

    enum Model {
        static let defaultName = "base"
        static let defaultLanguage = "en"

        /// Models shown in the menu: (id, display name)
        static let available: [(id: String, name: String)] = [
            ("tiny", "Tiny (~75 MB, fastest)"),
            ("base", "Base (~140 MB, default)"),
            ("small", "Small (~460 MB, better accuracy)"),
            ("large-v3", "Large v3 (~3 GB, best accuracy)"),
        ]
    }
}
