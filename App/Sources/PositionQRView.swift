import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import GridFixCore

struct PositionQRRequest: Identifiable {
    let id = UUID()
    let title: String
    let payload: String
    let caption: String

    init?(title: String, lat: Double, lon: Double, label: String, digits: Int = 10) {
        guard let payload = PositionShare.geoURI(lat: lat, lon: lon, label: label) else { return nil }
        self.title = title; self.payload = payload
        caption = MGRS.parts(lat: lat, lon: lon, digits: digits)?.full ?? Format.latLon(lat: lat, lon: lon, format: .decimalDegrees)
    }
}

enum PositionQRCode {
    static func image(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output.transformed(by: .init(scaleX: 8, y: 8)), from: output.extent.applying(.init(scaleX: 8, y: 8)))
    }
}

struct PositionQRView: View {
    let request: PositionQRRequest
    let night: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image = PositionQRCode.image(request.payload) {
                        Image(uiImage: UIImage(cgImage: image)).resizable().interpolation(.none).scaledToFit()
                            .padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Position QR code")
                            .accessibilityIdentifier("position-qr-image")
                    } else { Text("Could not build the QR code.") }
                    Text(request.caption).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("position-qr-caption")
                    Text("Scan with a compatible phone camera or QR reader to open this coordinate in a map app.")
                        .font(.callout).multilineTextAlignment(.center)
                    if night {
                        Text("The QR card stays white so it can be scanned.").font(.caption)
                    }
                }.foregroundStyle(FieldPalette(night: night).ink).padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
            .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.environment(\.fieldNight, night).fieldSheetAppearance()
    }
}
