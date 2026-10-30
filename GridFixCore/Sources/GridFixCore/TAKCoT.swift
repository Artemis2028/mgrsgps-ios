import Foundation

public struct TAKRemoteItem: Equatable, Sendable, Identifiable {
    public let id:String
    public let callsign:String
    public let affiliation:String
    public let points:[GeoPoint]
    public let closed:Bool
    public let isContact:Bool
    public let staleAt:Date
    public let creator:String?
}
public enum TAKEvent: Equatable, Sendable {
    case item(TAKRemoteItem),delete(String),other
}
public enum TAKCoT {
    public static let maximumEventCharacters=256*1024
    public static let maximumVertices=500
    public static let maximumStaleSeconds:TimeInterval=3600
    public static let sharedStaleSeconds:TimeInterval=600
    public struct Failure:LocalizedError,Equatable {
        public let message:String
        public init(message:String) {self.message=message}
        public var errorDescription:String? {message}
    }
    private static func escaped(_ value:String)->String {
        value.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;")
    }
    static func validPosition(_ point:GeoPoint)->Bool {
        TrackCodec.validCoordinates(point.lat,point.lon) && (point.lat != 0 || point.lon != 0)
    }
    private static func text(_ value:String,identity:Bool=false) throws {
        guard value.utf16.count <= (identity ? 512:1024),!identity || !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              value.unicodeScalars.allSatisfy({$0.value==9 || $0.value==10 || $0.value==13 || ($0.value>=32 && $0.value != 0xfffe && $0.value != 0xffff)}) else {throw Failure(message:"Invalid TAK name or identity")}
    }
    private static func iso(_ date:Date)->String {
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return formatter.string(from:date)
    }
    private static func head(_ uid:String,_ type:String,_ how:String,_ now:Date,_ life:TimeInterval) throws ->String {
        try text(uid,identity:true)
        guard now.timeIntervalSince1970.isFinite,abs(now.timeIntervalSince1970)<253402300799 else {throw Failure(message:"Invalid TAK event time")}
        return "<event version=\"2.0\" uid=\"\(escaped(uid))\" type=\"\(type)\" how=\"\(how)\" time=\"\(iso(now))\" start=\"\(iso(now))\" stale=\"\(iso(now.addingTimeInterval(life)))\">"
    }
    private static func point(_ p:GeoPoint,_ accuracy:Double=9999999)->String {
        String(format:"<point lat=\"%.7f\" lon=\"%.7f\" hae=\"9999999.0\" ce=\"%.1f\" le=\"9999999.0\"/>",locale:Locale(identifier:"en_US_POSIX"),p.lat,p.lon,accuracy)
    }
    private static func producer(_ uid:String,_ callsign:String,_ now:Date) throws ->String {
        try text(uid,identity:true);try text(callsign)
        return "<link uid=\"\(escaped(uid))\" production_time=\"\(iso(now))\" type=\"a-f-G-U-C\" parent_callsign=\"\(escaped(callsign))\" relation=\"p-p\"/>"
    }
    public static func presence(uid:String,callsign:String,team:String="Cyan",version:String="0.1.0",now:Date,position:GeoPoint?=nil,accuracy:Double=9999999) throws ->String {
        try text(callsign);try text(team);try text(version)
        if let position {guard validPosition(position),accuracy.isFinite,accuracy>=0 else {throw Failure(message:"TAK sharing needs a valid fresh position")}}
        let how=position == nil ? "h-g-i-g-o":"m-g"
        return try head(uid,"a-f-G-U-C",how,now,120)+point(position ?? .init(lat:0,lon:0),position == nil ? 9999999:max(1,accuracy)) +
            "<detail><contact callsign=\"\(escaped(callsign))\"/><__group name=\"\(escaped(team))\" role=\"Team Member\"/><takv device=\"iOS\" platform=\"MGRS GPS\" os=\"iOS\" version=\"\(escaped(version))\"/></detail></event>"
    }
    public static func ping(uid:String,now:Date) throws ->String {try head(uid+"-ping","t-x-c-t","h-g-i-g-o",now,20)+point(.init(lat:0,lon:0))+"<detail/></event>"}
    public static func marker(uid:String,name:String,affiliation:String,position:GeoPoint,creatorUID:String,creatorCallsign:String,now:Date) throws ->String {
        try text(name);guard validPosition(position) else {throw Failure(message:"Invalid TAK marker position")}
        let atom=["friendly":"f","hostile":"h","neutral":"n"][affiliation] ?? "u"
        return try head(uid,"a-\(atom)-G","h-g-i-g-o",now,sharedStaleSeconds)+point(position)+"<detail><contact callsign=\"\(escaped(name))\"/>"+producer(creatorUID,creatorCallsign,now)+"</detail></event>"
    }
    public static func drawing(uid:String,name:String,points:[GeoPoint],closed:Bool,creatorUID:String,creatorCallsign:String,now:Date) throws ->String {
        try text(name)
        guard points.count >= (closed ? 3:2),points.count+(closed ? 1:0)<=maximumVertices,points.allSatisfy(validPosition) else {throw Failure(message:"TAK drawings need valid points within the 500-vertex wire limit")}
        let vertices=closed ? points+[points[0]]:points
        let links=vertices.map {String(format:"<link point=\"%.7f,%.7f\"/>",locale:Locale(identifier:"en_US_POSIX"),$0.lat,$0.lon)}.joined()
        return try head(uid,"u-d-f","h-e",now,sharedStaleSeconds)+point(points[0])+"<detail><contact callsign=\"\(escaped(name))\"/>"+links+"<strokeColor value=\"-256\"/><strokeWeight value=\"3.0\"/>"+producer(creatorUID,creatorCallsign,now)+"</detail></event>"
    }
    public static func delete(uid:String,now:Date) throws ->String {
        try text(uid,identity:true)
        return try head(uid+"-delete","t-x-d-d","h-e",now,20)+point(.init(lat:0,lon:0))+"<detail><link uid=\"\(escaped(uid))\" relation=\"none\" type=\"none\"/><__forcedelete/></detail></event>"
    }
    public static func parse(_ xml:String,ownUID:String,now:Date)->TAKEvent? {
        guard xml.utf16.count<=maximumEventCharacters,now.timeIntervalSince1970.isFinite,
              xml.range(of:"<!DOCTYPE",options:.caseInsensitive)==nil,xml.range(of:"<!ENTITY",options:.caseInsensitive)==nil else {return nil}
        let reader=TAKCoTReader(),parser=XMLParser(data:Data(xml.utf8))
        parser.shouldResolveExternalEntities=false;parser.delegate=reader
        guard parser.parse(),reader.rootSeen,reader.depth==0,!reader.invalid,
              let uid=reader.uid,!uid.isEmpty,uid.utf16.count<=512,let type=reader.type,type.utf16.count<=128 else {return nil}
        if uid==ownUID || uid.hasPrefix(ownUID+"-") || reader.creator==ownUID && type != "t-x-d-d" {return .other}
        if type=="t-x-d-d" {return reader.deleteTarget.map(TAKEvent.delete) ?? .other}
        guard let stale=reader.stale else {return nil}
        let expiry=min(stale,now.addingTimeInterval(maximumStaleSeconds))
        let name=String(decoding:(reader.callsign ?? uid).utf16.prefix(60),as:UTF16.self)
        if type.hasPrefix("a-") {
            guard let position=reader.position,validPosition(position) else {return nil}
            let atom=type.split(separator:"-",omittingEmptySubsequences:false).dropFirst().first.map(String.init) ?? ""
            let affiliation=["f":"friendly","a":"friendly","h":"hostile","s":"hostile","j":"hostile","k":"hostile","n":"neutral"][atom] ?? "unknown"
            return .item(.init(id:uid,callsign:name,affiliation:affiliation,points:[position],closed:false,isContact:reader.hasDevice,staleAt:expiry,creator:reader.creator))
        }
        if ["u-d-f","u-d-r","u-d-c-c"].contains(type) {
            guard reader.points.count>=2 else {return nil}
            let repeated=reader.points.count>2 && reader.points.first==reader.points.last
            let closed=type=="u-d-r" || repeated
            let points=repeated ? Array(reader.points.dropLast()):reader.points
            guard !closed || points.count>=3 else {return nil}
            return .item(.init(id:uid,callsign:name,affiliation:"unknown",points:points,closed:closed,isContact:false,staleAt:expiry,creator:reader.creator))
        }
        return .other
    }
}

private final class TAKCoTReader:NSObject,XMLParserDelegate {
    var uid:String?,type:String?,stale:Date?,callsign:String?,creator:String?,deleteTarget:String?
    var position:GeoPoint?,points:[GeoPoint]=[]
    var hasDevice=false,rootSeen=false,invalid=false,depth=0
    private func time(_ text:String?)->Date? {
        guard let text else {return nil}
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let date=formatter.date(from:text) {return date}
        formatter.formatOptions=[.withInternetDateTime];return formatter.date(from:text)
    }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]) {
        depth+=1
        guard depth<=64 else {invalid=true;parser.abortParsing();return}
        if depth==1 {
            guard name=="event",!rootSeen else {invalid=true;parser.abortParsing();return}
            rootSeen=true;uid=a["uid"];type=a["type"];stale=time(a["stale"])
        } else if name=="event" {invalid=true;parser.abortParsing();return}
        switch name {
        case "point": position=nil; if let lat=a["lat"].flatMap(Double.init),let lon=a["lon"].flatMap(Double.init) {position = .init(lat:lat,lon:lon)}
        case "contact": callsign=a["callsign"] ?? callsign
        case "takv": hasDevice=true
        case "link":
            if let value=a["point"] {
                let parts=value.split(separator:",",omittingEmptySubsequences:false)
                if parts.count>=2,let lat=Double(parts[0].trimmingCharacters(in:.whitespaces)),let lon=Double(parts[1].trimmingCharacters(in:.whitespaces)),TAKCoT.validPosition(.init(lat:lat,lon:lon)) {
                    guard points.count<TAKCoT.maximumVertices else {invalid=true;parser.abortParsing();return}
                    points.append(.init(lat:lat,lon:lon))
                }
            } else if let linked=a["uid"],!linked.isEmpty,linked.utf16.count<=512 {
                if a["relation"]=="p-p" {creator=linked} else {deleteTarget=linked}
            }
        default:break
        }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {depth-=1}
}
