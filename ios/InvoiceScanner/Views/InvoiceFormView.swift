import SwiftUI
import SwiftData

/// 新增發票前的暫存資料（掃描結果或手動輸入）
struct InvoiceDraft: Identifiable {
    struct Item: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unitPrice: Double
    }

    let id = UUID()
    var number = ""
    var date = Date()
    var totalAmount = 0
    var sellerTaxID = ""
    var storeName = ""
    var storeAddress = ""
    var note = ""
    var items: [Item] = []
    var fromScan = false

    init() {}

    init(parsed p: ParsedInvoice) {
        number = p.number
        date = p.date
        totalAmount = p.totalAmount
        sellerTaxID = p.sellerTaxID
        items = p.items.map { Item(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice) }
        fromScan = true
    }
}

struct InvoiceFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var draft: InvoiceDraft
    @State private var lookingUp = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    LabeledContent("發票號碼") {
                        TextField("AB12345678", text: $draft.number)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                    }
                    DatePicker("消費日期", selection: $draft.date, displayedComponents: .date)
                    LabeledContent("金額") {
                        TextField("0", value: $draft.totalAmount, format: .number)
                            .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                }

                Section {
                    LabeledContent("賣方統編") {
                        TextField("8 碼", text: $draft.sellerTaxID)
                            .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                    TextField("店家名稱", text: $draft.storeName)
                    TextField("店家地址", text: $draft.storeAddress, axis: .vertical)
                    Button {
                        Task { await lookupStore() }
                    } label: {
                        HStack {
                            Text("依統編查詢店家資料")
                            if lookingUp { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(lookingUp || draft.sellerTaxID.count != 8)
                } header: { Text("店家") } footer: {
                    Text("發票 QR Code 不含店家地址，會以統一編號向經濟部商工登記資料查詢（顯示的是登記地址，不一定是門市地址），可自行修改。")
                }

                Section("品項") {
                    ForEach($draft.items) { $item in
                        VStack(alignment: .leading) {
                            TextField("品名", text: $item.name)
                            HStack {
                                TextField("數量", value: $item.quantity, format: .number)
                                    .keyboardType(.decimalPad)
                                Text("×")
                                TextField("單價", value: $item.unitPrice, format: .number)
                                    .keyboardType(.decimalPad)
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    Button("新增品項") {
                        draft.items.append(.init(name: "", quantity: 1, unitPrice: 0))
                    }
                }

                Section("備註") {
                    TextField("例如：公司報帳、和朋友聚餐…", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(draft.fromScan ? "確認發票" : "手動新增")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() } }
            }
            .alert("無法儲存", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task {
                if draft.fromScan && draft.storeName.isEmpty { await lookupStore() }
            }
        }
    }

    private func lookupStore() async {
        lookingUp = true
        defer { lookingUp = false }
        if let info = await StoreLookupService.lookup(taxID: draft.sellerTaxID) {
            if draft.storeName.isEmpty { draft.storeName = info.name }
            if draft.storeAddress.isEmpty { draft.storeAddress = info.address }
        }
    }

    private func save() {
        let number = draft.number.trimmingCharacters(in: .whitespaces).uppercased()
        if !number.isEmpty {
            let existing = try? context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.number == number }))
            if let existing, !existing.isEmpty {
                errorMessage = "發票 \(number) 已經記錄過了"
                return
            }
        }
        let invoice = Invoice(
            number: number.isEmpty ? "MANUAL-\(UUID().uuidString.prefix(8))" : number,
            date: draft.date, totalAmount: draft.totalAmount,
            sellerTaxID: draft.sellerTaxID, storeName: draft.storeName,
            storeAddress: draft.storeAddress, note: draft.note)
        context.insert(invoice)
        for (i, item) in draft.items.enumerated() where !item.name.isEmpty {
            let it = InvoiceItem(name: item.name, quantity: item.quantity, unitPrice: item.unitPrice, order: i)
            it.invoice = invoice
            context.insert(it)
        }
        dismiss()
    }
}
