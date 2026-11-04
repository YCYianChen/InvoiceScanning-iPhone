import Foundation

/// 解析台灣電子發票證明聯上的兩個 QR Code。
///
/// 左側 QR Code 前 77 碼為固定格式：
///   發票號碼(10) 開立日期民國年yyyMMdd(7) 隨機碼(4) 銷售額16進位(8)
///   總計額16進位(8) 買方統編(8) 賣方統編(8) 加密驗證資訊(24)
/// 之後以 ":" 分隔：營業人自行使用區(10) : 二維條碼記載品項數 : 交易品項總數 : 中文編碼參數 : 品名:數量:單價:...
/// 右側 QR Code 以 "**" 開頭，接續品項資訊。
struct ParsedInvoice: Equatable {
    struct Item: Equatable {
        var name: String
        var quantity: Double
        var unitPrice: Double
    }

    var number: String
    var date: Date
    var randomCode: String
    var salesAmount: Int
    var totalAmount: Int
    var buyerTaxID: String
    var sellerTaxID: String
    var items: [Item]
    /// 交易品項總數（發票上宣告的）
    var declaredItemCount: Int
}

enum EInvoiceParser {
    static func isLeftQRCode(_ s: String) -> Bool {
        guard s.count >= 77 else { return false }
        let head = Array(s.prefix(21))
        // 2 個英文字母 + 8 位數字 + 7 位日期 + 4 位隨機碼
        let letters = head[0...1].allSatisfy { $0.isASCII && $0.isUppercase }
        let digits = head[2...20].allSatisfy { $0.isASCII && $0.isNumber }
        return letters && digits
    }

    static func isRightQRCode(_ s: String) -> Bool { s.hasPrefix("**") }

    /// - Parameters:
    ///   - left: 左側 QR Code 內容
    ///   - right: 右側 QR Code 內容（可為 nil）
    static func parse(left: String, right: String? = nil) -> ParsedInvoice? {
        guard isLeftQRCode(left) else { return nil }
        let chars = Array(left)
        func sub(_ start: Int, _ len: Int) -> String { String(chars[start..<start + len]) }

        let number = sub(0, 10)
        guard let date = rocDate(sub(10, 7)) else { return nil }
        let random = sub(17, 4)
        let sales = Int(sub(21, 8), radix: 16) ?? 0
        let total = Int(sub(29, 8), radix: 16) ?? 0
        let buyer = sub(37, 8)
        let seller = sub(45, 8)

        var items: [ParsedInvoice.Item] = []
        var declaredCount = 0

        // 77 碼之後的部分，第一個字元應為 ":"
        var tail = String(chars.dropFirst(77))
        if tail.hasPrefix(":") { tail.removeFirst() }
        let headerFields = tail.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)

        if headerFields.count >= 4 {
            declaredCount = Int(headerFields[2]) ?? 0
            let encoding = headerFields[3]
            var itemsPart = headerFields.count == 5 ? headerFields[4] : ""
            var rightPart = ""
            if let right, isRightQRCode(right) { rightPart = String(right.dropFirst(2)) }

            if encoding == "2" {
                // Base64：左右分別解碼後再串接
                itemsPart = decodeBase64(itemsPart)
                rightPart = decodeBase64(rightPart)
            }
            items = parseItems(left: itemsPart, right: rightPart)
        }

        return ParsedInvoice(number: number, date: date, randomCode: random,
                             salesAmount: sales, totalAmount: total,
                             buyerTaxID: buyer, sellerTaxID: seller,
                             items: items, declaredItemCount: declaredCount)
    }

    /// 民國年 yyyMMdd → Date
    static func rocDate(_ s: String) -> Date? {
        guard s.count == 7, let y = Int(s.prefix(3)),
              let m = Int(s.dropFirst(3).prefix(2)), let d = Int(s.suffix(2)) else { return nil }
        var comps = DateComponents()
        comps.year = y + 1911
        comps.month = m
        comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private static func parseItems(left: String, right: String) -> [ParsedInvoice.Item] {
        // 品項可能跨左右兩個 QR Code。先直接串接；若欄位數不是 3 的倍數，改以 ":" 相接再試。
        let candidates: [String]
        if right.isEmpty {
            candidates = [left]
        } else {
            candidates = [left + right, left + ":" + right]
        }
        var best: [ParsedInvoice.Item] = []
        for joined in candidates {
            var fields = joined.split(separator: ":", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            while fields.last == "" { fields.removeLast() }
            let parsed = itemsFrom(fields)
            if fields.count % 3 == 0, !parsed.isEmpty { return parsed }
            if parsed.count > best.count { best = parsed }
        }
        return best
    }

    private static func itemsFrom(_ f: [String]) -> [ParsedInvoice.Item] {
        var result: [ParsedInvoice.Item] = []
        var i = 0
        while i + 2 < f.count {
            if let q = Double(f[i + 1]), let p = Double(f[i + 2]), !f[i].isEmpty {
                result.append(.init(name: f[i], quantity: q, unitPrice: p))
            }
            i += 3
        }
        return result
    }

    private static func decodeBase64(_ s: String) -> String {
        guard !s.isEmpty, let data = Data(base64Encoded: s) else { return s }
        return String(data: data, encoding: .utf8) ?? s
    }
}
