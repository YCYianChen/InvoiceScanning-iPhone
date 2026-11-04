import Foundation

/// 以賣方統一編號查詢店家名稱與地址。
/// 發票 QR Code 本身「不含」店家地址，因此透過經濟部商工登記公示資料開放 API 查詢。
/// 公司登記查無資料時，再查商業登記（行號）。
enum StoreLookupService {
    struct StoreInfo { var name: String; var address: String }

    static func lookup(taxID: String) async -> StoreInfo? {
        guard taxID.count == 8, taxID.allSatisfy(\.isNumber), taxID != "00000000" else { return nil }
        if let info = await query(
            api: "5F64D864-61CB-4D0D-8AD9-492047CC1EA6",
            filter: "Business_Accounting_NO eq \(taxID)",
            nameKey: "Company_Name", addressKey: "Company_Location") {
            return info
        }
        return await query(
            api: "7E6AFA72-AD6A-46D3-8681-ED77951D912D",
            filter: "President_No eq \(taxID)",
            nameKey: "Business_Name", addressKey: "Business_Address")
    }

    private static func query(api: String, filter: String, nameKey: String, addressKey: String) async -> StoreInfo? {
        var comps = URLComponents(string: "https://data.gcis.nat.gov.tw/od/data/api/\(api)")!
        comps.queryItems = [
            .init(name: "$format", value: "json"),
            .init(name: "$filter", value: filter),
            .init(name: "$skip", value: "0"),
            .init(name: "$top", value: "1"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = arr.first else { return nil }
            let name = (first[nameKey] as? String) ?? ""
            let address = (first[addressKey] as? String) ?? ""
            if name.isEmpty && address.isEmpty { return nil }
            return StoreInfo(name: name, address: address)
        } catch {
            return nil
        }
    }
}
