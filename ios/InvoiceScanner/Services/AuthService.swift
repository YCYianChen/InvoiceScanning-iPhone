import Foundation
import FirebaseAuth

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var user: User?
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        guard FirebaseConfig.isConfigured else { return }
        user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try? await result.user.sendEmailVerification()
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        try await Auth.auth().currentUser?.delete()
    }

    static func message(for error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .wrongPassword, .userNotFound, .invalidCredential: return "Email 或密碼錯誤"
        case .invalidEmail: return "Email 格式不正確"
        case .emailAlreadyInUse: return "這個 Email 已經註冊過，請直接登入"
        case .weakPassword: return "密碼至少要 6 個字元"
        case .tooManyRequests: return "嘗試次數太多，請稍後再試"
        case .networkError: return "網路連線失敗，請檢查網路"
        case .requiresRecentLogin: return "為了安全，請登出後重新登入，再刪除帳號"
        default: return error.localizedDescription
        }
    }
}
