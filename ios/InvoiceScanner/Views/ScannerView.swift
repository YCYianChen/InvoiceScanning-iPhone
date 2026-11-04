import SwiftUI
import VisionKit

/// 相機掃描畫面：同時辨識發票左右兩個 QR Code。
struct ScannerView: View {
    var onComplete: (ParsedInvoice) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var leftCode: String?
    @State private var rightCode: String?
    @State private var finished = false

    private var parsed: ParsedInvoice? {
        leftCode.flatMap { EInvoiceParser.parse(left: $0, right: rightCode) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ZStack(alignment: .bottom) {
                        DataScanner { payload in handle(payload) }
                            .ignoresSafeArea()
                        statusPanel
                    }
                } else {
                    ContentUnavailableView("無法使用相機掃描",
                        systemImage: "camera.fill",
                        description: Text("請確認已允許相機權限，且裝置支援（需 iPhone XS 以上、iOS 16+）。"))
                }
            }
            .navigationTitle("掃描發票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            Text("請將發票上的兩個 QR Code 同時放入畫面")
                .font(.subheadline)
            HStack(spacing: 20) {
                Label("左側 QR", systemImage: leftCode == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(leftCode == nil ? .secondary : Color.green)
                Label("右側 QR", systemImage: rightCode == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(rightCode == nil ? .secondary : Color.green)
            }
            if let p = parsed {
                Text("\(p.number)　$\(p.totalAmount)　已讀到 \(p.items.count)/\(p.declaredItemCount) 項")
                    .font(.footnote.monospaced())
                Button("使用目前結果") { finish() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func handle(_ payload: String) {
        if EInvoiceParser.isLeftQRCode(payload) {
            if leftCode != payload {
                // 換了一張發票才清掉右側資料
                if leftCode != nil { rightCode = nil }
                leftCode = payload
            }
        } else if EInvoiceParser.isRightQRCode(payload) {
            rightCode = payload
        }
        // 品項已讀齊就自動完成
        if let p = parsed, p.declaredItemCount > 0, p.items.count >= p.declaredItemCount {
            finish()
        } else if let p = parsed, rightCode != nil, p.declaredItemCount == 0 {
            finish()
        }
    }

    private func finish() {
        guard !finished, let p = parsed else { return }
        finished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(p)
        dismiss()
    }
}

/// 包裝 VisionKit 的 DataScannerViewController
private struct DataScanner: UIViewControllerRepresentable {
    var onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in allItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onPayload(value)
                }
            }
        }

        func dataScanner(_ s: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            dataScanner(s, didAdd: items, allItems: allItems)
        }
    }
}
