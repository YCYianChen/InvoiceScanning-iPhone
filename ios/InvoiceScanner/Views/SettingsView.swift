import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: InvoiceStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("帳號") {
                    LabeledContent("登入身分", value: auth.user?.email ?? "")
                    LabeledContent("同步狀態", value: store.syncStatus)
                    LabeledContent("發票數量", value: "\(store.invoices.count) 張")
                }
                Section {
                    Button("登出") { auth.signOut(); dismiss() }
                    Button("刪除帳號", role: .destructive) { confirmDelete = true }
                } footer: {
                    if let message { Text(message).foregroundStyle(.red) }
                    else { Text("網頁版和 App 登入同一個帳號就會同步。沒有網路時也能新增，連上網路後會自動上傳。") }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("會永久刪除帳號和雲端上所有發票，網頁版和 App 都會一起消失。",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("永久刪除", role: .destructive) { Task { await deleteAccount() } }
            }
        }
    }

    private func deleteAccount() async {
        do {
            try await store.deleteAll()
            try await auth.deleteAccount()
            dismiss()
        } catch {
            message = AuthService.message(for: error)
        }
    }
}
