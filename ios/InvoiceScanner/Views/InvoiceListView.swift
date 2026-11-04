import SwiftUI
import SwiftData

struct InvoiceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Invoice.date, order: .reverse) private var invoices: [Invoice]

    @State private var showScanner = false
    @State private var draft: InvoiceDraft?
    @State private var searchText = ""

    private var filtered: [Invoice] {
        guard !searchText.isEmpty else { return invoices }
        return invoices.filter { inv in
            inv.storeName.localizedCaseInsensitiveContains(searchText)
            || inv.note.localizedCaseInsensitiveContains(searchText)
            || inv.number.localizedCaseInsensitiveContains(searchText)
            || inv.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    /// 依消費日期（以天為單位）分組
    private var grouped: [(day: Date, invoices: [Invoice])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.invoices) { inv in
                            NavigationLink(value: inv) { InvoiceRow(invoice: inv) }
                        }
                        .onDelete { offsets in
                            offsets.map { group.invoices[$0] }.forEach(context.delete)
                        }
                    } header: {
                        HStack {
                            Text(group.day, format: .dateTime.year().month().day().weekday())
                            Spacer()
                            Text("小計 $\(group.invoices.reduce(0) { $0 + $1.totalAmount })")
                        }
                    }
                }
            }
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView("尚無發票",
                        systemImage: "doc.text.viewfinder",
                        description: Text("點右上角相機圖示掃描電子發票"))
                }
            }
            .searchable(text: $searchText, prompt: "搜尋店家、品項、備註")
            .navigationTitle("發票記錄")
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: { Image(systemName: "camera.viewfinder") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { draft = InvoiceDraft() } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerView { parsed in
                    // 等掃描畫面關閉後再開啟確認表單
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        draft = InvoiceDraft(parsed: parsed)
                    }
                }
            }
            .sheet(item: $draft) { d in
                InvoiceFormView(draft: d)
            }
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invoice.storeName.isEmpty ? "統編 \(invoice.sellerTaxID)" : invoice.storeName)
                    .font(.headline).lineLimit(1)
                Spacer()
                Text("$\(invoice.totalAmount)").font(.headline.monospacedDigit())
            }
            if !invoice.items.isEmpty {
                Text(invoice.sortedItems.map(\.name).joined(separator: "、"))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if !invoice.note.isEmpty {
                Label(invoice.note, systemImage: "note.text")
                    .font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }
}
