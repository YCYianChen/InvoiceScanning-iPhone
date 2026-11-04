import SwiftUI
import SwiftData
import MapKit

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    var body: some View {
        Form {
            Section("基本資訊") {
                LabeledContent("發票號碼", value: invoice.number)
                DatePicker("消費日期", selection: $invoice.date, displayedComponents: .date)
                LabeledContent("金額") {
                    TextField("0", value: $invoice.totalAmount, format: .number)
                        .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                }
            }

            Section("店家") {
                TextField("店家名稱", text: $invoice.storeName)
                TextField("店家地址", text: $invoice.storeAddress, axis: .vertical)
                LabeledContent("賣方統編", value: invoice.sellerTaxID)
                if !invoice.storeAddress.isEmpty {
                    Button {
                        openInMaps(invoice.storeAddress)
                    } label: { Label("在地圖中開啟", systemImage: "map") }
                }
            }

            Section("品項（\(invoice.items.count)）") {
                ForEach(invoice.sortedItems) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(item.quantity.formatted()) × \(item.unitPrice.formatted())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.subtotal.formatted()).monospacedDigit()
                    }
                }
                if invoice.items.isEmpty {
                    Text("無品項資料").foregroundStyle(.secondary)
                }
            }

            Section("備註") {
                TextField("新增備註…", text: $invoice.note, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle(invoice.storeName.isEmpty ? invoice.number : invoice.storeName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps(_ address: String) {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}
