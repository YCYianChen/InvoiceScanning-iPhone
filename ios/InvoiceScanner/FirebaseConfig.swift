import FirebaseCore

/// Firebase iOS 設定：Firebase 主控台 →「專案設定 → 一般 → 你的應用程式 → iOS 應用程式」
/// 下載的 GoogleService-Info.plist 裡可以找到這些值。它們不是密碼，資料安全由 firestore.rules 保護。
enum FirebaseConfig {
    static let googleAppID = "請填入"        // GOOGLE_APP_ID，例如 1:1234567890:ios:abcdef...
    static let gcmSenderID = "41359962481"        // GCM_SENDER_ID
    static let apiKey = "請填入"             // API_KEY
    static let projectID = "invoicescanning-iphone"          // PROJECT_ID

    static var isConfigured: Bool { !apiKey.hasPrefix("請填") }

    static func configure() {
        guard isConfigured else { return }
        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: gcmSenderID)
        options.apiKey = apiKey
        options.projectID = projectID
        FirebaseApp.configure(options: options)
    }
}
