import SwiftUI

struct TAKCertificateDetailsView: View {
    let info: TAKClientCertificateInfo
    let now: Date
    let night: Bool
    private var palette: FieldPalette { .init(night: night) }
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            Text("This device’s client certificate").font(.headline)
            Text(info.subject).font(.subheadline).textSelection(.enabled)
            Text(info.status(at: now)).font(.subheadline.weight(.semibold))
                .foregroundStyle(info.state(at: now) == .withinDates ? palette.ink : palette.warn)
                .accessibilityIdentifier("tak-client-certificate-status")
            if let dates = info.validity {
                Text("Valid from\n" + TAKClientCertificateInfo.dateLabel(dates.notBefore))
                    .font(.system(.caption,design: .monospaced)).accessibilityIdentifier("tak-client-certificate-start")
                Text("Expires\n" + TAKClientCertificateInfo.dateLabel(dates.notAfter))
                    .font(.system(.caption,design: .monospaced)).accessibilityIdentifier("tak-client-certificate-expiry")
            }
            Text("Client SHA-256\n" + info.sha256).font(.system(.caption,design: .monospaced)).textSelection(.enabled)
                .accessibilityIdentifier("tak-client-certificate-fingerprint")
            Text("These dates describe the client certificate. Server trust and certificate chains are checked when connecting.")
                .font(.footnote).foregroundStyle(palette.inkDim)
        }.fixedSize(horizontal: false,vertical: true).frame(maxWidth: .infinity,alignment: .leading)
            .padding(14).fieldChrome().foregroundStyle(palette.ink)
    }
}
