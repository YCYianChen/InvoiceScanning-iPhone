import Foundation
import SwiftData

@Model
final class Invoice {
    /// 發票號碼，例如 AB12345678
    @Attribute(.unique) var number: String
    /// 消費日期
    var date: Date
    /// 總金額（含稅）
    var totalAmount: Int
    /// 賣方統一編號
    var sellerTaxID: String
    /// 店家名稱（查詢或手動輸入）
    var storeName: String
    /// 店家地址（查詢或手動輸入）
    var storeAddress: String
    /// 使用者備註
    var note: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \InvoiceItem.invoice)
    var items: [InvoiceItem] = []

    init(number: String, date: Date, totalAmount: Int, sellerTaxID: String,
         storeName: String = "", storeAddress: String = "", note: String = "") {
        self.number = number
        self.date = date
        self.totalAmount = totalAmount
        self.sellerTaxID = sellerTaxID
        self.storeName = storeName
        self.storeAddress = storeAddress
        self.note = note
        self.createdAt = .now
    }

    var sortedItems: [InvoiceItem] { items.sorted { $0.order < $1.order } }
}

@Model
final class InvoiceItem {
    var name: String
    var quantity: Double
    var unitPrice: Double
    var order: Int
    var invoice: Invoice?

    init(name: String, quantity: Double, unitPrice: Double, order: Int) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.order = order
    }

    var subtotal: Double { quantity * unitPrice }
}
