import SwiftUI

/// 新增或編輯發票（掃描結果、手動新增、點清單開啟都用這個畫面）
struct InvoiceFormView: View {
    @EnvironmentObject private var store: InvoiceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State var invoice: Invoice
    let isNew: Bool
    let fromScan: Bool

    @State private var lookingUp = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    LabeledContent("發票號碼") {
                        TextField("AB12345678", text: $invoice.number)
                            .multilineTextAlignment(.trailing).monospaced()
                            .textInputAutocapitalization(.characters)
                    }
                    DatePicker("消費日期", selection: $invoice.dateValue, displayedComponents: .date)
                    LabeledContent("金額") {
                        TextField("0", value: $invoice.total, format: .number)
                            .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                }

                Section {
                    LabeledContent("賣方統編") {
                        TextField("8 碼", text: $invoice.sellerTaxID)
                            .multilineTextAlignment(.trailing).keyboardType(.numberPad).monospaced()
                    }
                    if suggestions.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("這個統編以前記錄過：").font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(suggestions, id: \.self) { c in
                                        Button {
                                            invoice.storeName = c.name
                                            invoice.storeAddress = c.address
                                        } label: {
                                            VStack(alignment: .leading) {
                                                Text(c.name).font(.subheadline)
                                                if !c.address.isEmpty {
                                                    Text(c.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                                }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                    TextField("店家名稱", text: $invoice.storeName)
                    TextField("店家地址", text: $invoice.storeAddress, axis: .vertical)
                    Button {
                        Task { await lookupStore() }
                    } label: {
                        HStack {
                            Text("依統編查詢店家")
                            if lookingUp { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(lookingUp || invoice.sellerTaxID.count != 8)
                    if !invoice.storeAddress.isEmpty || !invoice.storeName.isEmpty {
                        Button { openInMaps() } label: { Label("在地圖開啟", systemImage: "map") }
                    }
                } header: { Text("店家") } footer: {
                    Text("發票 QR Code 不含地址。查詢結果是經濟部商工登記的「公司登記地址」，不一定是門市地址，請自行修改。")
                }

                Section {
                    ForEach($invoice.items) { $item in
                        VStack(alignment: .leading) {
                            TextField("品名", text: $item.name)
                            HStack {
                                TextField("數量", value: $item.qty, format: .number).keyboardType(.decimalPad)
                                Text("×")
                                TextField("單價", value: $item.price, format: .number).keyboardType(.decimalPad)
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { invoice.items.remove(atOffsets: $0) }
                    Button("新增品項") { invoice.items.append(.init(name: "", qty: 1, price: 0)) }
                } header: { Text("品項") } footer: {
                    if !invoice.items.isEmpty {
                        Text("品項合計 \(invoice.items.reduce(0) { $0 + $1.subtotal }.money)")
                    }
                }

                Section("備註") {
                    TextField("例如：公司報帳、和朋友聚餐…", text: $invoice.note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !isNew {
                    Section {
                        Button("刪除這張發票", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? (fromScan ? "確認發票" : "手動新增") : "發票內容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() } }
            }
            .alert("無法儲存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") {}
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog("確定刪除？刪除後無法復原，網頁版也會一起刪除。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) { store.delete(invoice); dismiss() }
            }
            .task {
                if fromScan && invoice.storeName.isEmpty && suggestions.isEmpty { await lookupStore() }
            }
        }
    }

    struct StoreCombo: Hashable { let name: String; let address: String }

    /// 你以前為同一個統編填過的店名＋地址（去除重複，最近的在前）
    static func storeCombos(for taxID: String, in invoices: [Invoice], excluding id: String?) -> [StoreCombo] {
        guard !taxID.isEmpty else { return [] }
        var seen = Set<StoreCombo>()
        return invoices
            .filter { $0.sellerTaxID == taxID && !$0.storeName.isEmpty && $0.id != id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { StoreCombo(name: $0.storeName, address: $0.storeAddress) }
            .filter { seen.insert($0).inserted }
            .prefix(6).map { $0 }
    }

    private var suggestions: [StoreCombo] {
        isNew ? Self.storeCombos(for: invoice.sellerTaxID, in: store.invoices, excluding: invoice.id) : []
    }

    private func lookupStore() async {
        lookingUp = true
        defer { lookingUp = false }
        if let info = await StoreLookupService.lookup(taxID: invoice.sellerTaxID) {
            if invoice.storeName.isEmpty { invoice.storeName = info.name }
            if invoice.storeAddress.isEmpty { invoice.storeAddress = info.address }
        }
    }

    private func openInMaps() {
        let q = invoice.storeAddress.isEmpty ? invoice.storeName : invoice.storeAddress
        var comps = URLComponents(string: "https://maps.apple.com/")!
        comps.queryItems = [.init(name: "q", value: q)]
        if let url = comps.url { openURL(url) }
    }

    private func save() {
        invoice.number = invoice.number.trimmingCharacters(in: .whitespaces).uppercased()
        if store.isDuplicate(number: invoice.number, excluding: invoice.id) {
            errorMessage = "發票 \(invoice.number) 已經記錄過了"
            return
        }
        invoice.items.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        store.save(invoice)
        dismiss()
    }
}
