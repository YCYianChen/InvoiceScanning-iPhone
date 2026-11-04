import SwiftUI

struct InvoiceListView: View {
    @EnvironmentObject private var store: InvoiceStore

    @State private var showScanner = false
    @State private var showSettings = false
    @State private var editor: EditorRequest?
    @State private var searchText = ""
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start

    struct EditorRequest: Identifiable {
        let id = UUID()
        var invoice: Invoice
        var isNew: Bool
        var fromScan: Bool
    }

    private var monthKey: String { String(Invoice.dayString(from: month).prefix(7)) }
    private var inMonth: [Invoice] { store.invoices.filter { $0.date.hasPrefix(monthKey) } }

    private var shown: [Invoice] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return inMonth }
        return store.invoices.filter { inv in
            ([inv.storeName, inv.note, inv.number, inv.storeAddress] + inv.items.map(\.name))
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// 依消費日期分組
    private var grouped: [(day: String, invoices: [Invoice])] {
        let dict = Dictionary(grouping: shown, by: \.date)
        return dict.keys.sorted(by: >).map { day in
            (day, dict[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section {
                        HStack {
                            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                            Text(month, format: .dateTime.year().month(.wide)).font(.headline)
                            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(inMonth.reduce(0) { $0 + $1.total }.money)
                                    .font(.title2.bold().monospacedDigit())
                                Text("共 \(inMonth.count) 張").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.invoices) { inv in
                            Button {
                                editor = .init(invoice: inv, isNew: false, fromScan: false)
                            } label: { InvoiceRow(invoice: inv) }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            offsets.map { group.invoices[$0] }.forEach(store.delete)
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(group.day))
                            Spacer()
                            Text("小計 \(group.invoices.reduce(0) { $0 + $1.total }.money)")
                        }
                    }
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "這個月還沒有發票" : "找不到「\(searchText)」",
                        systemImage: "doc.text.viewfinder",
                        description: Text(searchText.isEmpty ? "點右上角相機圖示掃描電子發票" : ""))
                }
            }
            .searchable(text: $searchText, prompt: "搜尋店家、品項、備註")
            .navigationTitle("發票記帳")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        editor = .init(invoice: Invoice(), isNew: true, fromScan: false)
                    } label: { Image(systemName: "square.and.pencil") }
                    Button { showScanner = true } label: { Image(systemName: "camera.viewfinder") }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerView { parsed in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openScanned(parsed) }
                }
            }
            .sheet(item: $editor) { req in
                InvoiceFormView(invoice: req.invoice, isNew: req.isNew, fromScan: req.fromScan)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("發生錯誤", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("好") {}
            } message: { Text(store.lastError ?? "") }
        }
    }

    private func openScanned(_ p: ParsedInvoice) {
        if let dup = store.existing(number: p.number) {
            editor = .init(invoice: dup, isNew: false, fromScan: false)
            return
        }
        var inv = Invoice()
        inv.number = p.number
        inv.dateValue = p.date
        inv.total = Double(p.totalAmount)
        inv.sellerTaxID = p.sellerTaxID
        inv.items = p.items.map { InvoiceItem(name: $0.name, qty: $0.quantity, price: $0.unitPrice) }
        // 這個統編以前只對應過一組店名時才自動沿用；多組時讓使用者在表單裡選
        let combos = InvoiceFormView.storeCombos(for: p.sellerTaxID, in: store.invoices, excluding: nil)
        if combos.count == 1 {
            inv.storeName = combos[0].name
            inv.storeAddress = combos[0].address
        }
        editor = .init(invoice: inv, isNew: true, fromScan: true)
    }

    private func shiftMonth(_ delta: Int) {
        month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func dayTitle(_ day: String) -> String {
        let d = Invoice.date(fromDay: day)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = searchText.isEmpty ? "M 月 d 日（EEEEE）" : "yyyy 年 M 月 d 日（EEEEE）"
        return f.string(from: d)
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invoice.displayName).font(.headline).lineLimit(1)
                Spacer()
                Text(invoice.total.money).font(.headline.monospacedDigit())
            }
            if !invoice.items.isEmpty {
                Text(invoice.items.map(\.name).joined(separator: "、"))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if !invoice.note.isEmpty {
                Label(invoice.note, systemImage: "note.text")
                    .font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }
}
