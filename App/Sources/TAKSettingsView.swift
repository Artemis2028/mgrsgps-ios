import GridFixCore
import SwiftUI
import UniformTypeIdentifiers

struct TAKSettingsView: View {
    @EnvironmentObject private var tak: TAKSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var importer = false
    @State private var importing = false
    @State private var callsign = ""
    var onShow: ((TAKRemoteItem) -> Void)?
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tak.status).font(.headline).accessibilityIdentifier("tak-status")
                    if let error = tak.failure { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("tak-error") }
                    Button(importing ? "Importing…" : "Import connection package") { importer = true }
                        .disabled(importing).accessibilityIdentifier("tak-import")
                    if tak.configured {
                        Text(tak.profile.title).font(.headline)
                        Text("\(tak.profile.host):\(tak.profile.port) · \(tak.profile.tls ? "TLS" : "Unencrypted TCP")")
                            .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        if !tak.profile.tls { Text("This connection is unencrypted. Its traffic can be read or changed on the network.").foregroundStyle(palette.warn) }
                        TextField("Callsign", text: $callsign).textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().accessibilityIdentifier("tak-callsign")
                            .onSubmit { tak.setCallsign(callsign) }
                        Button(tak.connected || tak.connecting ? "Disconnect" : "Connect") {
                            tak.setCallsign(callsign)
                            if tak.connected || tak.connecting { tak.disconnect() } else { tak.connect() }
                        }.accessibilityIdentifier("tak-connect")
                        Toggle("Share my position", isOn: $tak.sharePosition).tint(palette.accent).accessibilityIdentifier("tak-share-position")
                        Text("Off by default. Connecting announces your callsign without a position. Sharing uses location and may continue while locked after you start it here. iOS can suspend receive-only connections; they resume when you return.")
                            .font(.footnote).foregroundStyle(palette.inkDim)
                        if tak.isSyntheticValidation { Text("SYNTHETIC TEST POSITION · LOCAL SERVER ONLY").foregroundStyle(palette.warn).font(.caption) }
                        Toggle("Show TAK layer", isOn: Binding(get: { tak.profile.showRemote }, set: { tak.setRemoteVisible($0) }))
                            .tint(palette.accent).accessibilityIdentifier("tak-show-layer")
                        if let certificate = tak.trustRequest {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Server name does not match").font(.headline)
                                Text("Requested: \(tak.profile.host)")
                                Text("Subject: \(certificate.subject)")
                                Text("Certificate names: \(certificate.names.isEmpty ? "No subject alternative names" : certificate.names.joined(separator: ", "))")
                                Text("SHA-256\n\(certificate.sha256)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text("Verify this fingerprint with your server administrator. Trusting pins this certificate for this endpoint; a changed certificate is refused.").font(.footnote)
                                Button("Trust this certificate") { tak.approveCertificate() }.accessibilityIdentifier("tak-trust-certificate")
                                Button("Cancel", role: .cancel) { tak.declineCertificate() }
                            }.padding().fieldChrome()
                        }
                        SectionLabel(text: "Shared folders")
                        Text("None shared by default. Shares visible waypoints, lines and areas. Hiding an item or closing its folder eye withdraws it, including after reconnecting. Rings, sectors and text labels stay local.").font(.footnote).foregroundStyle(palette.inkDim)
                        ForEach(tak.availableFolders, id: \.self) { folder in
                            Toggle(folder, isOn: Binding(get: { tak.sharedFolders.contains(folder) }, set: { tak.setFolderShared(folder, shared: $0) })).tint(palette.accent)
                        }
                        SectionLabel(text: "Remote items · \(tak.remoteItems.count)")
                        Text("Read-only server layer. Items expire automatically and are not added to your saved waypoints.").font(.footnote).foregroundStyle(palette.inkDim)
                        ForEach(tak.remoteItems) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.callsign).font(.headline)
                                    Spacer()
                                    if let onShow { Button("Show on map") { onShow(item); dismiss() } }
                                }
                                Text(item.isContact ? "Contact · \(item.affiliation)" : item.points.count == 1 ? "Marker · \(item.affiliation)" : item.closed ? "Area" : "Line").font(.caption).foregroundStyle(palette.inkDim)
                                if let point = item.points.first { Text(MGRS.parts(lat: point.lat, lon: point.lon, digits: settings.mgrsDigits)?.full ?? String(format: "%.7f, %.7f", point.lat, point.lon)).font(.system(.caption, design: .monospaced)) }
                            }.padding().fieldChrome().accessibilityIdentifier("tak-remote-\(item.id)")
                        }
                        Text(tak.profile.uid).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("tak-device-uid")
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-uiTestTAKLocal") {
                        if FileManager.default.fileExists(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tak-local-validation.zip").path) {
                            Text("Local fixture available").accessibilityIdentifier("tak-local-fixture-ready")
                        }
                        Button("Load local validation package") {
                            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tak-local-validation.zip")
                            Task {
                                if let bytes = try? Data(contentsOf: file) { await tak.importPackage(bytes); tak.enableLocalValidation(); callsign = "IOS-LOCAL-TEST"; tak.setCallsign(callsign) }
                            }
                        }.accessibilityIdentifier("tak-local-validation")
                    }
                    #endif
                }.padding(20).foregroundStyle(palette.ink)
            }.background(palette.background.ignoresSafeArea())
                .navigationTitle("TAK server").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { tak.setCallsign(callsign); dismiss() } } }
                .tint(palette.accent)
        }.preferredColorScheme(.dark)
            .onAppear { callsign = tak.profile.callsign }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.zip, .data]) { result in
                guard case let .success(url) = result else { return }
                importing = true
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() }; importing = false }
                    do {
                        let bytes = try await Task.detached {
                            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                            let bytes = try handle.read(upToCount: TAKConnectionPackage.maximumFileBytes + 1) ?? Data()
                            guard bytes.count <= TAKConnectionPackage.maximumFileBytes else { throw TAKCoT.Failure(message: "Connection package exceeds 8 MiB") }
                            return bytes
                        }.value
                        await tak.importPackage(bytes); callsign = tak.profile.callsign
                    } catch { tak.reportImportFailure(error.localizedDescription) }
                }
            }
    }
}
