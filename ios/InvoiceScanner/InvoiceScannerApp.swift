import SwiftUI
import SwiftData

@main
struct InvoiceScannerApp: App {
    var body: some Scene {
        WindowGroup {
            InvoiceListView()
        }
        .modelContainer(for: [Invoice.self, InvoiceItem.self])
    }
}
