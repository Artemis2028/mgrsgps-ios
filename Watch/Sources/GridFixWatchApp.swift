import SwiftUI
import CoreText
import GridFixCore

@main
struct GridFixWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchGlanceView(model: model)
                #if DEBUG
                .transformEnvironment(\.dynamicTypeSize) { size in
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-watchUITesting"), args.contains("-watchLargeText") { size = .accessibility3 }
                }
                #endif
                .onAppear { model.setActive(phase == .active) }
                .onChange(of: phase) { _, value in model.setActive(value == .active) }
        }
    }
}

struct WatchGlanceView: View {
    @ObservedObject var model: WatchModel
    @State private var selection = 0
    @State private var showDetails = false
    @State private var showMap = false
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 13
    @AppStorage("watch.mgrs.digits") private var precisionOverride = 0
    private var digits: Int { [4, 6, 8, 10].contains(precisionOverride) ? precisionOverride : model.snapshot.mgrsDigits }
    // -1 follows the phone; 0/1 is a persistent local override for disconnected use.
    @AppStorage("watch.night.preference") private var nightPreference = -1
    private var night: Bool { nightPreference == -1 ? model.snapshot.nightMode : nightPreference == 1 }
    private var ink: Color { night ? Color(red: 1, green: 0.23, blue: 0.19) : Color(red: 0.961, green: 0.961, blue: 0.941) }
    private var accent: Color { night ? ink : Color(red: 1, green: 0.698, blue: 0) }
    private var good: Color { night ? ink : Color(red: 0.749, green: 1, blue: 0.478) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            TabView(selection: $selection) {
                positionPage(date: timeline.date).tag(0)
                page(date: timeline.date, navigation: true).tag(1)
                mapLauncher(date: timeline.date).tag(2)
            }
            .tabViewStyle(.page)
            .background(Color.black)
            .foregroundStyle(ink)
            .tint(accent)
        }
        .onChange(of: selection) { _, value in if value == 2 { showMap = true } }
        .fullScreenCover(isPresented: $showMap) {
            WatchMapView(model: model, night: night, showPosition: { showMap = false; selection = 0 }, closeMap: { showMap = false })
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showDetails) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        label("LOCATION DETAILS")
                        fixStatus(date: timeline.date)
                        connectionStatus(date: timeline.date)
                        nightControls
                        Button("Done") { showDetails = false }
                    }.padding(.horizontal, 8)
                }.foregroundStyle(ink).tint(accent).background(Color.black)
            }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-watchNavigate") { selection = 1 }
            if args.contains("-watchMap") { selection = 2 }
            if args.contains("-watchUITesting") {
                if let i = args.firstIndex(of: "-watchPrecision"), i + 1 < args.count {
                    let value = args[i + 1]
                    if value == "phone" { precisionOverride = 0 }
                    else if let n = Int(value), [4, 6, 8, 10].contains(n) { precisionOverride = n }
                }
                if let i = args.firstIndex(of: "-watchNight"), i + 1 < args.count {
                    switch args[i + 1] {
                    case "phone": nightPreference = -1
                    case "day": nightPreference = 0
                    case "night": nightPreference = 1
                    default: break
                    }
                }
                if args.contains("-watchDetails") { showDetails = true }
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ text: String, color: Color? = nil) -> some View {
        Text(text).font(.custom("SairaSemiCondensed-SemiBold", size: 11)).foregroundStyle(color ?? accent).lineLimit(1).minimumScaleFactor(0.7)
    }
    private func number(_ text: String, size: CGFloat = 32) -> some View {
        Text(text).font(.custom("Antonio-Bold", size: size)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
    }
    private func page(date: Date, navigation: Bool) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    label(navigation ? "NAV" : "MGRS")
                    Spacer(minLength: 4)
                    if let fix = model.fix {
                        label(String(format: "±%.0fM", fix.horizontalAccuracy) + " · " + age(date.timeIntervalSince(fix.timestamp)),
                              color: model.usable(at: date) ? good : accent)
                    }
                }
                navigationContent(date: date)
                phoneGuidance(date: date).id("phoneGuidance")
                Divider().overlay(accent.opacity(0.3))
                fixStatus(date: date)
                connectionStatus(date: date)
                nightControls
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        #if DEBUG
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-watchUITesting"),args.contains("-watchPhoneGuide") {
                try? await Task.sleep(nanoseconds:200_000_000)
                proxy.scrollTo("phoneGuidance",anchor:.top)
            }
        }
        #endif
        }
    }

    private func mapLauncher(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("MAP")
            if let map = model.mapSnapshot {
                Text("\(map.waypoints.count) waypoints · \(map.features.count) field items").font(.caption)
                label("CACHED · " + age(date.timeIntervalSince(map.updatedAt)))
            } else { Text(model.mapSyncStatus).font(.caption) }
            Button("Open map") { showMap = true }.frame(minHeight: 44)
            label("FULL SCREEN · PAN / ZOOM")
        }.padding(.horizontal, 8)
    }

    private func connectionStatus(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(model.reachable ? "PHONE REACHABLE" : "PHONE NOT REACHABLE")
            if model.hasSync { label("CACHED SYNC · \(age(date.timeIntervalSince(model.snapshot.updatedAt)))") }
            else { label("OPEN IPHONE TO SYNC TARGET") }
        }
    }

    /// The primary position instrument never scrolls. Only diagnostics/settings use the sheet.
    private func positionPage(date: Date) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 4)
            let columnWidth = max(0, width - 47)
            let heightLimit = max(36, ((geometry.size.height - headerHeight - 24) / 2 - 2) / WatchDigitMetrics.inkHeight)
            let widthLimit = columnWidth / (WatchDigitMetrics.advance * CGFloat(digits / 2))
            let numeralSize = min(52, heightLimit, widthLimit)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    label("WATCH")
                    Spacer(minLength: 0)
                    if let fix = model.fix {
                        label(String(format: "±%.0fM", fix.horizontalAccuracy) + " · " + age(date.timeIntervalSince(fix.timestamp)),
                              color: model.usable(at: date) ? good : accent)
                    } else { label("NO FIX") }
                }
                gridContent(date: date, size: numeralSize, width: width)
            }
            .frame(width: width, alignment: .topLeading)
            .padding(.horizontal, 2)
        }
    }

    private func gridNumeral(_ text: String, size: CGFloat, width: CGFloat) -> some View {
        // Antonio has substantial blank ascender/descender space. Retain every digit's
        // ink bounds, but remove that blank line-box space so two large rows fit.
        Text(text).font(.custom("Antonio-Bold", fixedSize: size)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.95)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .drawingGroup()
            .offset(y: 1 - size * WatchDigitMetrics.topBlank)
            .frame(height: ceil(size * WatchDigitMetrics.inkHeight) + 2, alignment: .top)
            .clipped()
    }

    @ViewBuilder private func gridContent(date: Date, size: CGFloat, width: CGFloat) -> some View {
        let usable = model.usable(at: date)
        let parts = model.fix.flatMap { usable ? MGRS.parts(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, digits: digits) : nil }
        Button { showDetails = true } label: {
            HStack {
                Text(parts.map { $0.gzd + " " + $0.square } ?? "MGRS")
                    .font(.custom("FiraMono-Regular", fixedSize: 12))
                Spacer()
                Image(systemName: "info.circle").font(.system(size: 13))
            }.foregroundStyle(accent).frame(width: width, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(parts.map { $0.gzd + " " + $0.square } ?? "MGRS"). Location details and night mode")
        HStack(alignment: .center, spacing: 3) {
            VStack(alignment: .leading, spacing: 2) {
                if let parts {
                    gridNumeral(parts.easting, size: size, width: max(0, width - 47)).accessibilityLabel("Easting \(parts.easting)")
                    gridNumeral(parts.northing, size: size, width: max(0, width - 47)).accessibilityLabel("Northing \(parts.northing)")
                } else {
                    Text("— —").font(.custom("Antonio-Bold", fixedSize: min(size, 38)))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: max(0, width - 47), alignment: .leading)
                    label(usable ? "OUTSIDE MGRS COVERAGE" : unavailableReason)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(width: max(0, width - 47), alignment: .leading)
            precisionControl.frame(width: 44).fixedSize(horizontal: true, vertical: true)
        }.frame(width: width, alignment: .leading)
    }

    private var unavailableReason: String {
        if model.reducedAccuracy { return "PRECISE LOCATION REQUIRED" }
        if let fix = model.fix {
            return fix.horizontalAccuracy > NavigationFixPolicy.maxAccuracyMeters ? "POOR ACCURACY" : "STALE FIX"
        }
        return model.status.uppercased()
    }

    private var precisionControl: some View {
        VStack(spacing: 2) {
            Text("FORMAT").font(.custom("SairaSemiCondensed-SemiBold", fixedSize: 10)).foregroundStyle(accent)
            Button {
                let order = [4, 6, 8, 10]
                precisionOverride = order[((order.firstIndex(of: digits) ?? 3) + 1) % order.count]
            } label: {
                Text("\(digits)D").font(.custom("FiraMono-Regular", fixedSize: 14))
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Grid format, \(digits) digits")
            .accessibilityHint("Cycles 4, 6, 8, and 10 digits. GPS accuracy is shown separately.")
            if precisionOverride != 0 {
                Button { precisionOverride = 0 } label: {
                    Text("PHONE").font(.custom("SairaSemiCondensed-SemiBold", fixedSize: 11)).frame(width: 44, height: 24)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Follow phone grid precision")
            }
        }.foregroundStyle(accent)
    }

    @ViewBuilder private func navigationContent(date: Date) -> some View {
        if let target = model.snapshot.target {
            Text(target.name).font(.custom("SairaSemiCondensed-SemiBold", size: 14)).lineLimit(2)
            if model.usable(at: date), let fix = model.fix {
                let nav = Geodesy.navInfo(fromLat: fix.coordinate.latitude, fromLon: fix.coordinate.longitude, toLat: target.lat, toLon: target.lon)
                let bearing = model.snapshot.bearing(trueDegrees: nav.bearingTrue, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude, altitude: fix.altitude, date: date)
                number(Format.distance(meters: nav.distanceMeters, unit: DistanceUnit(rawValue: model.snapshot.units) ?? .metric), size: 30)
                if nav.distanceMeters <= fix.horizontalAccuracy {
                    label("WITHIN FIX UNCERTAINTY")
                } else if let bearing {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        number(Format.angle(degrees: bearing, unit: AngleUnit(rawValue: model.snapshot.angleUnit) ?? .degrees), size: 30)
                        label(["TRUE", "MAG · " + (model.snapshot.declinationOverride == nil ? "WMM" : "SET"), "GRID"][model.snapshot.northRef])
                    }
                } else { label("MAGNETIC REF UNAVAILABLE") }
                label("BEARING TO TARGET · NO COMPASS")
            } else {
                number("—", size: 40)
                label("NEEDS FRESH PRECISE FIX")
            }
        } else {
            Text("No waypoint selected").font(.headline)
            label("SELECT ONE ON IPHONE")
        }
    }

    private func phoneGuidance(date: Date) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Divider().overlay(accent.opacity(0.3))
            label("PHONE GUIDANCE")
            if let guide = model.guideSnapshot {
                if guide.active,let name = guide.targetName { Text(name).font(.caption).fixedSize(horizontal:false,vertical:true) }
                Text(guide.displayStatus(at:date)).font(.caption).fixedSize(horizontal:false,vertical:true)
                if guide.isFresh(at:date),guide.active,guide.available {
                    if let name = guide.laneName { Text(name).font(.caption2) }
                    if let line = guide.crossedLine { Text("Limit: " + line).font(.caption2) }
                }
                label("PHONE · " + age(date.timeIntervalSince1970-Double(guide.at)/1000))
            } else { Text("Open phone to sync guide").font(.caption) }
            Text("Read-only · no watch alerts").font(.caption2).foregroundStyle(accent)
        }.accessibilityIdentifier("watch-phone-guidance")
    }

    private func fixStatus(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(model.status.uppercased(), color: model.usable(at: date) ? good : accent)
            if let fix = model.fix {
                label(String(format: "±%.0f M", fix.horizontalAccuracy) + " · \(age(date.timeIntervalSince(fix.timestamp)))" + (model.usable(at: date) ? "" : " · NOT NAV"))
            }
        }
    }
    private var nightControls: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Night mode", isOn: Binding(get: { night }, set: { nightPreference = $0 ? 1 : 0 }))
                .font(.custom("SairaSemiCondensed-SemiBold", size: 14))
                .accessibilityHint("Overrides phone night mode on this watch")
            if nightPreference != -1 {
                Button("Follow phone night mode") { nightPreference = -1 }
                    .font(.custom("SairaSemiCondensed-SemiBold", size: 12))
                    .accessibilityHint("Resumes using the latest phone setting")
            } else { label("NIGHT MODE FOLLOWS PHONE") }
        }
    }

    private func age(_ seconds: TimeInterval) -> String { WatchFixPolicy.ageLabel(seconds) }
}

/// Normalize the bundled Antonio digit metrics once; this is layout, not a drawn font substitute.
/// Measuring all digits preserves rounded tops/bottoms and tabular advance when trimming blank leading.
private enum WatchDigitMetrics {
    private static let values: (height: CGFloat, top: CGFloat, advance: CGFloat) = {
        let size: CGFloat = 48
        let font = CTFontCreateWithName("Antonio-Bold" as CFString, size, nil)
        var characters = Array("0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        let ink = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, nil, glyphs.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
        return (ink.height / size, (CTFontGetAscent(font) - ink.maxY) / size,
                (advances.map(\.width).max() ?? size / 2) / size)
    }()
    static var inkHeight: CGFloat { values.height }
    static var topBlank: CGFloat { values.top }
    static var advance: CGFloat { values.advance }
}
