import GridFixCore
import SwiftUI

/// Offline pocket reference, matching Android release/1.1.0 ReferenceScreen.
struct FieldReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    private var palette: FieldPalette { .init(night: night) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 12) {
                    ReferenceSection("Phonetic alphabet",id:"phonetic",expanded:true) {
                        ViewThatFits(in:.horizontal) {
                            HStack(alignment:.top,spacing:24) {
                                alphabet("ABCDEFGHIJKLM")
                                alphabet("NOPQRSTUVWXYZ")
                            }
                            alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                        }
                        Divider()
                        ViewThatFits(in:.horizontal) {
                            HStack(alignment:.top,spacing:24) { digits("01234"); digits("56789") }
                            digits("0123456789")
                        }
                    }
                    ReferenceSection("Sending a grid by radio",id:"radio") {
                        paragraph("Announce “grid”, spell each character phonetically, and pause between groups. Example: 18T VP 3808 9755.")
                        Text("Grid " + Phonetic.mgrsSpeech("18T VP 3808 9755"))
                            .font(.system(.body,design:.monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("reference-radio-example")
                        paragraph("Position shows your grid spelled out and can speak it aloud.")
                    }
                    ReferenceSection("Reading an MGRS grid",id:"grid") {
                        paragraph("Read RIGHT, then UP. The grid zone (18T) and 100 km square (VP) come first. Split the remaining even number of digits equally: easting, then northing.")
                        row("4 digits","1 km grid square")
                        row("6 digits","100 m grid square")
                        row("8 digits","10 m grid square")
                        row("10 digits","1 m grid square")
                        paragraph("Digit count describes grid precision, not GPS accuracy. Check the reported accuracy and fix age before using a position.")
                            .accessibilityIdentifier("reference-grid-accuracy")
                    }
                    ReferenceSection("Pace count",id:"pace") {
                        paragraph("Count each time the same foot strikes: every other footfall. Calibrate over a measured 100 m course three times with your usual load, then use the average in Settings. Route cards use your paces per 100 m.")
                        paragraph("A typical starting range is 55–75 paces per 100 m. Your measured count matters: slope, ground, load and visibility change it.")
                        row("Uphill / soft ground","Often more paces")
                        row("Downhill / firm road","Often fewer paces; recalibrate for steep descents")
                        row("Night / fog / rain","Conditions can increase your count")
                        row("With a rucksack","Your load may increase your count")
                        paragraph("Move a pace bead, or a pebble between pockets, every 100 m. Ten 100 m counts equal 1 km.")
                    }
                    ReferenceSection("Contours & terrain shapes",id:"contours") {
                        paragraph("Contours join equal elevations. The contour interval is the elevation step between lines. Close lines mean steep ground; widely spaced lines mean gentler ground. Check the interval on the map you are using. Heavier, labelled index contours help you keep track of elevation.")
                        row("Hilltop","Closed rings, highest inside")
                        row("Ridge","U/V shapes pointing downhill")
                        row("Valley / draw","U/V shapes pointing uphill")
                        row("Saddle","Hourglass between two highs")
                        row("Spur","Short ridge off a hillside")
                        row("Depression","Closed rings with inward ticks")
                        row("Cliff","Contours touch or merge")
                    }
                    ReferenceSection("North references & declination",id:"north") {
                        paragraph("True north points to the geographic pole. Grid north follows the map's vertical grid lines. Magnetic north follows the compass needle. Declination is the true-to-magnetic angle; the grid-to-magnetic (G-M) angle differs by grid convergence.")
                        row("Magnetic → True","Add east-positive declination")
                        row("True → Grid","Subtract grid convergence")
                        row("Declination","G-M angle + grid convergence")
                        paragraph("Declination changes with location and date; convergence depends on the grid location. The app's WMM declination and Field tools diagram show these references. Choose True, Magnetic or Grid in Settings.")
                    }
                    ReferenceSection("Symbols & affiliation",id:"symbols") {
                        row("Blue rectangle","Friendly unit")
                        row("Red diamond","Hostile unit")
                        row("Green square","Neutral unit")
                        row("Yellow clover","Unknown unit")
                        paragraph("Echelon marks sit above unit frames: dots for smaller units, I for company, II for battalion and X for brigade. Use the selected symbol's catalog label to identify its echelon.")
                        paragraph("Night mode uses red on black. Hostile tactical graphics carry ENY so affiliation does not depend on color alone.")
                    }
                    Text("Training aid. Verify against your unit's SOP, current doctrine and the map's own legend.")
                        .font(.footnote).foregroundStyle(palette.inkDim)
                        .accessibilityIdentifier("reference-training-note")
                }.padding(16)
            }.background { FieldScreenBackground() }
                .foregroundStyle(palette.ink)
                .navigationTitle("Field reference").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.principal) { Text("Field reference").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(palette.accent) }
                }
        }.tint(palette.accent).fieldSheetAppearance()
        #if DEBUG
        .transformEnvironment(\.dynamicTypeSize) { size in
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiTesting"), args.contains("-uiTestReferenceLargeText") { size = .accessibility5 }
        }
        #endif
    }
    private func paragraph(_ value: String) -> some View { Text(value).fixedSize(horizontal:false,vertical:true) }
    private func row(_ name: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:2) {
            Text(name).font(.system(.subheadline,design:.monospaced,weight:.semibold))
            Text(value).font(.subheadline)
        }.accessibilityElement(children:.combine)
    }
    private func alphabet(_ keys: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            ForEach(Array(keys),id:\.self) { key in phonetic(key,Phonetic.letters[key] ?? "") }
        }
    }
    private func digits(_ keys: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            ForEach(Array(keys),id:\.self) { key in phonetic(key,Phonetic.digits[key] ?? "") }
        }
    }
    private func phonetic(_ key: Character,_ word: String) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:12) {
            Text(String(key)).font(.system(.body,design:.monospaced,weight:.semibold)).frame(minWidth:20,alignment:.leading)
            Text(word).fixedSize(horizontal:true,vertical:false)
        }.accessibilityElement(children:.ignore).accessibilityLabel("\(key), \(word)")
    }
}

private struct ReferenceSection<Content: View>: View {
    let title: String
    let id: String
    let content: () -> Content
    @State private var expanded: Bool
    init(_ title: String,id: String,expanded: Bool = false,@ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.id = id; self.content = content; _expanded = State(initialValue:expanded)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Button { expanded.toggle() } label: {
                HStack { Text(title).font(.headline).multilineTextAlignment(.leading); Spacer(); Image(systemName:expanded ? "chevron.up" : "chevron.down") }
                    .frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("reference-"+id)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content() }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).fieldChrome()
    }
}
