import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var signUp = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 48)).foregroundStyle(.tint)
                        Text("發票記帳").font(.title.bold())
                        Text("登入後，iPhone App 和網頁版的發票會自動同步。")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密碼（至少 6 個字元）", text: $password)
                        .textContentType(signUp ? .newPassword : .password)
                } footer: {
                    if let message { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text(signUp ? "註冊並登入" : "登入").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)

                    Button(signUp ? "已經有帳號？登入" : "還沒有帳號？註冊") { signUp.toggle(); message = nil }
                    Button("忘記密碼") { Task { await reset() } }
                } footer: {
                    Text("發票存在你的帳號裡（Google Firebase），傳輸和儲存都有加密。資料庫的安全規則只允許你本人登入後讀寫自己的發票，其他使用者看不到。")
                }
            }
        }
    }

    private func submit() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            let e = email.trimmingCharacters(in: .whitespaces)
            if signUp { try await auth.signUp(email: e, password: password) }
            else { try await auth.signIn(email: e, password: password) }
            password = ""
        } catch {
            message = AuthService.message(for: error)
        }
    }

    private func reset() async {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { message = "請先在上方輸入 Email"; return }
        do {
            try await auth.resetPassword(email: e)
            message = "已寄出重設密碼信，請收信"
        } catch {
            message = AuthService.message(for: error)
        }
    }
}
