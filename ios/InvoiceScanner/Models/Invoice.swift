import Foundation
import FirebaseFirestore

/// 與網頁版共用的資料格式：Firestore 的 users/{uid}/invoices/{id}
struct Invoice: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var number: String = ""
    /// 消費日期，格式 yyyy-MM-dd
    var date: String = Invoice.dayString(from: .now)
    var total: Double = 0
    var sellerTaxID: String = ""
    var storeName: String = ""
    var storeAddress: String = ""
    var note: String = ""
    var items: [InvoiceItem] = []
    /// 毫秒時間戳記（與網頁版的 Date.now() 一致）
    var createdAt: Double = Date.now.timeIntervalSince1970 * 1000
    var updatedAt: Double = Date.now.timeIntervalSince1970 * 1000

    init() {}

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func dayString(from date: Date) -> String { dayFormatter.string(from: date) }
    static func date(fromDay day: String) -> Date { dayFormatter.date(from: day) ?? .now }

    var dateValue: Date {
        get { Self.dayFormatter.date(from: date) ?? .now }
        set { date = Self.dayString(from: newValue) }
    }

    var displayName: String {
        if !storeName.isEmpty { return storeName }
        if !sellerTaxID.isEmpty { return "統編 \(sellerTaxID)" }
        return "未命名店家"
    }
}

struct InvoiceItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var qty: Double
    var price: Double

    enum CodingKeys: String, CodingKey { case name, qty, price }

    init(name: String, qty: Double, price: Double) {
        self.name = name; self.qty = qty; self.price = price
    }
    var subtotal: Double { qty * price }
}

extension Double {
    var money: String { "$" + Int(self.rounded()).formatted() }
}
