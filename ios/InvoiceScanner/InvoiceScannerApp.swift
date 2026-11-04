import SwiftUI

@main
struct InvoiceScannerApp: App {
    @StateObject private var auth: AuthService
    @StateObject private var store = InvoiceStore()

    init() {
        FirebaseConfig.configure()
        _auth = StateObject(wrappedValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !FirebaseConfig.isConfigured {
                    ContentUnavailableView("尚未設定雲端同步", systemImage: "icloud.slash",
                        description: Text("請在 FirebaseConfig.swift 填入 Firebase 設定後重新編譯。"))
                } else if let user = auth.user {
                    InvoiceListView()
                        .onAppear { store.start(uid: user.uid) }
                        .onChange(of: user.uid) { _, uid in store.start(uid: uid) }
                } else {
                    AuthView()
                        .onAppear { store.stop() }
                }
            }
            .environmentObject(auth)
            .environmentObject(store)
        }
    }
}
