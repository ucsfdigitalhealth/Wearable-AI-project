import Foundation

/// Study-wide settings that aren't secrets. Fill these in when they're known.
enum StudyConfig {
    /// The Dropbox app key from https://www.dropbox.com/developers/apps (ask Ali to create the
    /// study's Dropbox app). Also set it in Support/Info-extra.plist as the URL scheme `db-<key>`.
    /// An app key is public by design (the app secret is not used by mobile apps).
    static let dropboxAppKey = "z28ia98g76mplwe"

    /// Which data source to use: the simulator or a real Polar Verity Sense.
    /// Changed from Study & Settings; takes effect after restarting the app.
    static var useRealDevice: Bool {
        UserDefaults.standard.bool(forKey: "useRealDevice")
    }

    /// Whether this build can talk to a real device / Dropbox at all.
    static var polarAvailable: Bool {
        #if POLAR_SDK
        true
        #else
        false
        #endif
    }

    static var dropboxAvailable: Bool {
        #if DROPBOX_SDK
        !dropboxAppKey.isEmpty
        #else
        false
        #endif
    }
}
