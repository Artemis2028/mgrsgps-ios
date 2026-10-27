import GridFixCore
import SwiftUI

struct TAKEnrollmentView: View {
    @EnvironmentObject private var tak: TAKSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var enrollmentPort = "8446"
    @State private var streamPort = "8089"
    @State private var username = ""
    @State private var password = ""
    @State private var link = ""
    @State private var verified: TAKEnrollmentClient.VerifiedServer?
    @State private var approval: TAKServerTrust.Certificate?
    @State private var error: String?
    @State private var busy = false
    @State private var worker: Task<Void, Never>?
    @FocusState private var focused: String?
    private let renewal: TAKSession.Renewal?
    init(suggestion: TAKEnrollment.Target? = nil,renewal: TAKSession.Renewal? = nil,usernameSuggestion: String? = nil) {
        self.renewal = renewal
        _username = State(initialValue: usernameSuggestion ?? "")
        _host = State(initialValue: suggestion?.host ?? "")
        _enrollmentPort = State(initialValue: String(suggestion?.enrollmentPort ?? 8446))
        _streamPort = State(initialValue: String(suggestion?.streamPort ?? 8089))
    }
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your server issues a certificate for this device. The private key stays in its Keychain; your password or token is used only for sign-in.")
                        .font(.footnote).foregroundStyle(palette.inkDim)
                    VStack(alignment: .leading, spacing: 12) {
                        field("Server hostname or IP", text: $host, id: "tak-enroll-host")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Sign-in port").font(.caption)
                                field("8446", text: $enrollmentPort, id: "tak-enroll-port").keyboardType(.numberPad)
                            }
                            VStack(alignment: .leading) {
                                Text("Stream port").font(.caption)
                                field("8089", text: $streamPort, id: "tak-enroll-stream-port").keyboardType(.numberPad)
                            }
                        }
                    }.disabled(busy || verified != nil || approval != nil || renewal != nil)
                    if let verified {
                        Label("Server verified", systemImage: "checkmark.shield").font(.headline)
                        Text("SHA-256\n" + fingerprint(verified.certificate.sha256)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        field("Username", text: $username, id: "tak-enroll-username").textContentType(.username)
                        SecureField("Password or token", text: $password, prompt: Text("Password or token").foregroundColor(palette.inkDim)).textContentType(.password)
                            .focused($focused, equals: "password").submitLabel(.done).onSubmit { focused = nil }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(12).background(palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("tak-enroll-password")
                        Button(busy ? "Signing in…" : "Sign in") { signIn(verified) }
                            .frame(minHeight: 44).buttonStyle(.borderedProminent).foregroundStyle(busy || username.isEmpty || password.isEmpty ? palette.inkDim : .black)
                            .disabled(busy || username.isEmpty || password.isEmpty).accessibilityIdentifier("tak-enroll-submit")
                        if !busy { Button(renewal == nil ? "Change server" : "Verify server again") { self.verified = nil; password = "" }.frame(minHeight: 44).buttonStyle(.bordered) }
                    } else if let approval {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Verify this server").font(.headline)
                            Text("iOS cannot confirm this certificate for the requested server. Confirm the fingerprint with your server administrator before trusting it.")
                                .font(.footnote)
                            Text("Requested: \(host)")
                            Text("Subject: " + approval.subject)
                            Text("Certificate names: " + (approval.names.isEmpty ? "None provided" : approval.names.joined(separator: ", ")))
                            Text("SHA-256\n" + fingerprint(approval.sha256)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("Trust applies to this exact certificate. A changed certificate is refused; expired or invalid chains cannot be approved.")
                                .font(.footnote).foregroundStyle(palette.inkDim)
                            Button("Trust this certificate") { verify(pin: approval.sha256) }.disabled(busy)
                                .frame(minHeight: 44).buttonStyle(.borderedProminent).foregroundStyle(busy ? palette.inkDim : .black)
                                .accessibilityIdentifier("tak-enroll-trust")
                            Button(renewal == nil ? "Use another server" : "Cancel renewal") {
                                if renewal == nil { self.approval = nil } else { cancel(); dismiss() }
                            }.disabled(busy).frame(minHeight: 44).buttonStyle(.bordered)
                        }.padding().fieldChrome()
                    } else {
                        Button(busy ? "Checking server…" : "Verify server") { verify() }.disabled(busy || host.isEmpty)
                            .frame(minHeight: 44).buttonStyle(.borderedProminent).foregroundStyle(busy || host.isEmpty ? palette.inkDim : .black)
                            .accessibilityIdentifier("tak-enroll-verify")
                        Text("No username, password or token is sent until the server is verified.")
                            .font(.footnote).foregroundStyle(palette.inkDim)
                        if renewal == nil {
                            Divider()
                            Text("Have an enrollment link?").font(.headline)
                            // Enrollment links can contain a secret token. Use a
                            // secure field and never echo the link in an error.
                            SecureField("Paste TAK enrollment link", text: $link, prompt: Text("Paste TAK enrollment link").foregroundColor(palette.inkDim)).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused, equals: "link").submitLabel(.done).onSubmit { focused = nil }
                                .padding(12).background(palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("tak-enroll-link")
                            Button("Use enrollment link") { applyLink() }.disabled(busy || link.isEmpty).frame(minHeight: 44).buttonStyle(.bordered)
                        }
                    }
                    if busy { ProgressView().tint(palette.accent) }
                    if let error { Text(error).foregroundStyle(palette.warn).font(.footnote).accessibilityIdentifier("tak-enroll-error") }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-uiTestTAKEnrollmentLocal"),
                       FileManager.default.fileExists(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tak-local-enrollment-ui-optin").path) {
                        Text("LOCAL ENROLLMENT UI VALIDATION").font(.caption).accessibilityIdentifier("tak-enroll-local-fixture-ready")
                    }
                    #endif
                }.padding(20).foregroundStyle(palette.ink)
            }.background(palette.background.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if focused != nil {
                        HStack {
                            Spacer()
                            Button("Done") { focused = nil }.fieldGlassButton().accessibilityIdentifier("tak-enroll-keyboard-done")
                        }.padding(.horizontal, 20).padding(.vertical, 4).background(palette.background)
                    }
                }
                .navigationTitle("Sign in to TAK").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel(); dismiss() }.accessibilityIdentifier("tak-enroll-cancel") }
                    ToolbarItem(placement: .principal) { Text("Sign in to TAK").font(.headline).foregroundStyle(palette.ink) }
                }
                .tint(palette.accent)
        }.preferredColorScheme(.dark).onDisappear { cancel() }
            .interactiveDismissDisabled(busy)
    }
    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundColor(palette.inkDim)).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused, equals: id).submitLabel(.done).onSubmit { focused = nil }
            .padding(12).background(palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier(id)
    }
    private func fingerprint(_ value: String) -> String {
        let octets = value.split(separator: ":")
        return stride(from: 0, to: octets.count, by: 8).map { octets[$0..<min($0 + 8, octets.count)].joined(separator: ":") }.joined(separator: "\n")
    }
    private func target() throws -> TAKEnrollment.Target {
        guard let enrollmentPort = Int(enrollmentPort), let streamPort = Int(streamPort) else {
            throw TAKCoT.Failure(message: "Enter valid sign-in and stream ports")
        }
        let target = try TAKEnrollment.Target(host: host,enrollmentPort: enrollmentPort,streamPort: streamPort)
        guard renewal == nil || target == renewal?.target else { throw TAKCoT.Failure(message: "Renewal uses the saved server. Cancel to choose a different server.") }
        return target
    }
    private func verify(pin: String? = nil) {
        focused = nil; error = nil
        do {
            let target = try target(); busy = true
            worker = Task { @MainActor in
                defer { busy = false; worker = nil }
                do {
                    let result = try await TAKEnrollmentClient.verify(target, approvedPin: pin ?? renewal?.pin)
                    try Task.checkCancellation(); verified = result; approval = nil
                } catch let request as TAKEnrollmentClient.NeedsApproval {
                    if !Task.isCancelled { approval = request.certificate }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func signIn(_ server: TAKEnrollmentClient.VerifiedServer) {
        focused = nil; busy = true; error = nil
        let username = username, password = password, deviceUID = tak.profile.uid
        self.password = ""
        worker = Task { @MainActor in
            defer { busy = false; worker = nil }
            do {
                let result = try await TAKEnrollmentClient.enroll(server: server, username: username, password: password, deviceUID: deviceUID)
                try Task.checkCancellation()
                try tak.installEnrollment(result,renewal: renewal)
                dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func applyLink() {
        do {
            let value = try TAKEnrollment.link(link)
            host = value.target.host; streamPort = String(value.target.streamPort); enrollmentPort = String(value.target.enrollmentPort)
            username = value.username; password = value.token; link = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func cancel() { worker?.cancel(); worker = nil; password = ""; link = "" }
}
