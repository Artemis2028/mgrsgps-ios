import GridFixCore
import SwiftUI

struct PositionSunRows:View {
    let point:GeoPoint
    let night:Bool
    @State private var reading:PositionSunReadout?
    private struct Key:Hashable {
        let latitude:Int
        let longitude:Int
        let window:Int
        let zone:String
    }
    var body:some View {
        TimelineView(.periodic(from:.now,by:600)) { timeline in
            let zone=TimeZone.autoupdatingCurrent
            let key=Key(latitude:Int(point.lat*100),longitude:Int(point.lon*100),window:Int(timeline.date.timeIntervalSince1970/600),zone:zone.identifier)
            VStack(alignment:.leading,spacing:5) {
                if let reading {
                    ForEach(reading.events) { event in
                        HStack(alignment:.firstTextBaseline) {
                            Text(event.id).font(Blackout.label(10)).tracking(1.2).frame(width:78,alignment:.leading)
                            Text(event.value).font(Blackout.numerals(13)).fixedSize(horizontal:false,vertical:true)
                        }.accessibilityElement(children:.combine).accessibilityIdentifier("position-sun-"+event.id.lowercased())
                    }
                    Text("L · "+reading.zone+"   Z · UTC").font(Blackout.label(10)).fixedSize(horizontal:false,vertical:true)
                }
            }.foregroundStyle(FieldPalette(night:night).ink)
                .task(id:key) { reading=PositionSunReadout(point:point,date:timeline.date,timeZone:zone) }
        }
    }
}
