import Foundation

/// Identifiers that must not collide with an installed copy of upstream VoiceInk.
enum AppIdentity {
    static let bundleIdentifier = "com.qaws81877.sulsul"
    #if DEBUG
    /// Debug (Sulsul Dev) keeps its own data and Keychain items so it never touches Release data.
    /// SULSUL_SUPPORT_DIR_NAME lets a verification run point it at a scratch folder.
    static let supportDirectoryName = ProcessInfo.processInfo.environment["SULSUL_SUPPORT_DIR_NAME"]
        .flatMap { $0.isEmpty || $0.contains("/") ? nil : $0 } ?? "com.qaws81877.sulsul.dev"
    static let keychainService = "com.qaws81877.sulsul.dev"  // secret-scan:allow Keychain service name, not a credential
    #else
    static let supportDirectoryName = "com.qaws81877.sulsul"
    static let keychainService = "com.qaws81877.sulsul"
    #endif
    static let keychainServiceLocalBuild = "com.qaws81877.sulsul.Local"
    static let loggerSubsystem = "com.qaws81877.sulsul"
    static var displayName: String {
        String(localized: "Sulsul")
    }
    static let productName = "Sulsul"
    static let sparklePublicKeyPlaceholder = "REPLACE_WITH_SPARKLE_PUBLIC_KEY"
    static let sparkleFeedURL = "https://github.com/qaws81877/sulsul/releases/latest/download/appcast.xml"

    static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }
}
