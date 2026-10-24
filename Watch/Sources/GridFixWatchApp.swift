import SwiftUI
import GridFixCore

@main
struct GridFixWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchGlanceView(model: model)
                .onAppear { model.setActive(phase == .active) }
                .onChange(of: phase) { _, value in model.setActive(value == .active) }
        }
    }
}

struct WatchGlanceView: View {
    @ObservedObject var model: WatchModel
    @State private var selection = 0
    // -1 follows the phone; 0/1 is a persistent local override for disconnected use.
    @AppStorage("watch.night.preference") private var nightPreference = -1
    private var night: Bool { nightPreference == -1 ? model.snapshot.nightMode : nightPreference == 1 }
    private var ink: Color { night ? Color(red: 1, green: 0.23, blue: 0.19) : Color(red: 0.961, green: 0.961, blue: 0.941) }
    private var accent: Color { night ? ink : Color(red: 1, green: 0.698, blue: 0) }
    private var good: Color { night ? ink : Color(red: 0.749, green: 1, blue: 0.478) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            TabView(selection: $selection) {
                page(date: timeline.date, navigation: false).tag(0)
                page(date: timeline.date, navigation: true).tag(1)
            }
            .tabViewStyle(.page)
            .background(Color.black)
            .foregroundStyle(ink)
            .tint(accent)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-watchNavigate") { selection = 1 }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ text: String, color: Color? = nil) -> some View {
        Text(text).font(.custom("SairaSemiCondensed-SemiBold", size: 11)).foregroundStyle(color ?? accent).lineLimit(1).minimumScaleFactor(0.7)
    }
    private func number(_ text: String, size: CGFloat = 48) -> some View {
        Text(text).font(.custom("Antonio-Bold", size: size)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
    }
    private func page(date: Date, navigation: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                label(navigation ? "NAVIGATE" : "POSITION · MGRS")
                if navigation { navigationContent(date: date) }
                else { gridContent(date: date) }
                Divider().overlay(accent.opacity(0.3))
                fixStatus(date: date)
                label(model.reachable ? "PHONE REACHABLE" : "PHONE NOT REACHABLE")
                if model.hasSync {
                    label("CACHED SYNC · \(age(date.timeIntervalSince(model.snapshot.updatedAt)))")
                } else { label("OPEN IPHONE TO SYNC TARGET") }
                nightControls
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func gridContent(date: Date) -> some View {
        if model.usable(at: date), let fix = model.fix {
            if let p = MGRS.parts(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude, digits: model.snapshot.mgrsDigits) {
                Text(p.gzd + " " + p.square).font(.custom("FiraMono-Regular", size: 12)).foregroundStyle(accent)
                number(p.easting)
                number(p.northing)
            } else {
                number("— —", size: 42)
                label("OUTSIDE MGRS COVERAGE")
            }
        } else {
            number("— —", size: 42)
            label(model.reducedAccuracy ? "PRECISE LOCATION REQUIRED" : "WAITING FOR FRESH FIX")
        }
    }

    @ViewBuilder private func navigationContent(date: Date) -> some View {
        if let target = model.snapshot.target {
            Text(target.name).font(.headline).lineLimit(2)
            if model.usable(at: date), let fix = model.fix {
                let nav = Geodesy.navInfo(fromLat: fix.coordinate.latitude, fromLon: fix.coordinate.longitude, toLat: target.lat, toLon: target.lon)
                let bearing = model.snapshot.bearing(trueDegrees: nav.bearingTrue, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude, altitude: fix.altitude, date: date)
                number(Format.distance(meters: nav.distanceMeters, unit: DistanceUnit(rawValue: model.snapshot.units) ?? .metric), size: 38)
                if nav.distanceMeters <= fix.horizontalAccuracy {
                    label("WITHIN FIX UNCERTAINTY")
                } else if let bearing {
                    number(Format.angle(degrees: bearing, unit: AngleUnit(rawValue: model.snapshot.angleUnit) ?? .degrees), size: 38)
                    label(["TRUE BEARING", "MAG BEARING · " + (model.snapshot.declinationOverride == nil ? "WMM" : "SET"), "GRID BEARING"][model.snapshot.northRef])
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
