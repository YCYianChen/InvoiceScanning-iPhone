import Foundation
import FirebaseFirestore

/// 即時同步使用者的發票。Firestore 在 iOS 預設開啟離線快取：沒網路時也能新增，連線後自動上傳。
@MainActor
final class InvoiceStore: ObservableObject {
    @Published private(set) var invoices: [Invoice] = []
    @Published private(set) var syncStatus = ""
    @Published var lastError: String?

    private var listener: ListenerRegistration?
    private var uid: String?

    private var collection: CollectionReference? {
        uid.map { Firestore.firestore().collection("users").document($0).collection("invoices") }
    }

    func start(uid: String) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        listener = collection?.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.lastError = "讀取資料失敗：\(error.localizedDescription)"; return }
                guard let snap else { return }
                self.invoices = snap.documents.compactMap { try? $0.data(as: Invoice.self) }
                self.syncStatus = snap.metadata.hasPendingWrites ? "有資料等待上傳…"
                    : snap.metadata.isFromCache ? "離線中，顯示手機上的資料" : "已同步"
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        uid = nil
        invoices = []
    }

    func isDuplicate(number: String, excluding id: String?) -> Bool {
        !number.isEmpty && invoices.contains { $0.number == number && $0.id != id }
    }

    func existing(number: String) -> Invoice? {
        invoices.first { $0.number == number }
    }

    /// 新增或更新。新發票以發票號碼當文件 ID，避免網頁版和 App 重複記錄。
    func save(_ invoice: Invoice) {
        guard let collection else { return }
        var inv = invoice
        inv.updatedAt = Date.now.timeIntervalSince1970 * 1000
        let docID = inv.id ?? (Self.isInvoiceNumber(inv.number) ? inv.number : UUID().uuidString)
        inv.id = nil
        do {
            try collection.document(docID).setData(from: inv) { [weak self] error in
                if let error { Task { @MainActor in self?.lastError = "同步失敗：\(error.localizedDescription)" } }
            }
        } catch {
            lastError = "儲存失敗：\(error.localizedDescription)"
        }
    }

    func delete(_ invoice: Invoice) {
        guard let id = invoice.id else { return }
        collection?.document(id).delete()
    }

    func deleteAll() async throws {
        guard let collection else { return }
        let snap = try await collection.getDocuments()
        for chunk in stride(from: 0, to: snap.documents.count, by: 400) {
            let batch = Firestore.firestore().batch()
            snap.documents[chunk..<min(chunk + 400, snap.documents.count)].forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }

    static func isInvoiceNumber(_ s: String) -> Bool {
        s.range(of: #"^[A-Z]{2}\d{8}$"#, options: .regularExpression) != nil
    }
}
