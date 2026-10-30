import Foundation

/// Ephemeral import material. The native credential store must import keys into
/// the app's Keychain and must never persist these passwords in ordinary settings.
public struct TAKServerPackage:Sendable {
    public let description:String
    public let host:String
    public let port:Int
    public let usesTLS:Bool
    public let caPKCS12:Data?
    public let caPassword:String?
    public let clientPKCS12:Data?
    public let clientPassword:String?
    public init(description:String,host:String,port:Int,usesTLS:Bool,caPKCS12:Data?,caPassword:String?,clientPKCS12:Data?,clientPassword:String?) {
        self.description=description;self.host=host;self.port=port;self.usesTLS=usesTLS
        self.caPKCS12=caPKCS12;self.caPassword=caPassword;self.clientPKCS12=clientPKCS12;self.clientPassword=clientPassword
    }
    public var needsEnrollment:Bool {usesTLS && clientPKCS12==nil}
}
public enum TAKConnectionPackage {
    public static let maximumFileBytes=8*1024*1024
    public static func read(_ bytes:Data) throws ->TAKServerPackage {
        guard bytes.count<=maximumFileBytes else {throw TAKCoT.Failure(message:"TAK connection package exceeds 8 MiB")}
        var files:[(String,Data)]=[]
        try ZipArchive.visit(bytes,limits:.init(entryBytes:2*1024*1024,totalBytes:maximumFileBytes,entries:256,backupRules:false)) {name,data in
            try Task.checkCancellation()
            if !name.hasSuffix("/") {files.append((name,data))}
        }
        let preferences=try files.filter {$0.0.lowercased().hasSuffix(".pref")}.map {try parsePreferences($0.1)}
        guard let stream=preferences.first(where:{$0["connectString0"] != nil}),let connect=stream["connectString0"] else {throw TAKCoT.Failure(message:"No TAK server in this package: connectString0 is missing")}
        var entries:[String:String]=[:]
        for preference in preferences {entries.merge(preference,uniquingKeysWith:{$1})}
        entries.merge(stream,uniquingKeysWith:{$1})
        guard let protocolSeparator=connect.lastIndex(of:":") else {throw TAKCoT.Failure(message:"TAK address must be host:port:protocol")}
        let address=connect[..<protocolSeparator],transport=connect[connect.index(after:protocolSeparator)...].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard let portSeparator=address.lastIndex(of:":"),let port=Int(address[address.index(after:portSeparator)...].trimmingCharacters(in:.whitespaces)),(1...65535).contains(port) else {throw TAKCoT.Failure(message:"Invalid TAK server port")}
        var host=address[..<portSeparator].trimmingCharacters(in:.whitespacesAndNewlines)
        if host.hasPrefix("["),host.hasSuffix("]") {host=String(host.dropFirst().dropLast())}
        guard !host.isEmpty,host.utf16.count<=1024,!host.contains(where:{$0.isWhitespace || $0.isNewline || $0=="/" || $0=="\\"}),host.unicodeScalars.allSatisfy({$0.value>=32}) else {throw TAKCoT.Failure(message:"Invalid TAK server address")}
        guard ["ssl","tls","tcp"].contains(transport) else {throw TAKCoT.Failure(message:"This TAK transport is not supported")}
        func file(_ location:String?)->Data? {
            guard let location,!location.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
            if let exact=files.first(where:{$0.0==location}) {return exact.1}
            let name=location.replacingOccurrences(of:"\\",with:"/").split(separator:"/").last.map(String.init) ?? ""
            let matches=files.filter {$0.0.split(separator:"/").last.map(String.init)?.caseInsensitiveCompare(name) == .orderedSame}
            return matches.count==1 ? matches[0].1:nil
        }
        let caLocation=entries["caLocation0"] ?? entries["caLocation"],clientLocation=entries["certificateLocation0"] ?? entries["certificateLocation"]
        let ca=file(caLocation),client=file(clientLocation)
        if let caLocation,!caLocation.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,ca==nil {throw TAKCoT.Failure(message:"The server CA named by the package is missing or ambiguous")}
        if let clientLocation,!clientLocation.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,client==nil {throw TAKCoT.Failure(message:"The client certificate named by the package is missing or ambiguous")}
        return .init(description:String((stream["description0"].flatMap {$0.isEmpty ? nil:$0} ?? host).prefix(200)),host:host,port:port,usesTLS:transport != "tcp",caPKCS12:ca,caPassword:entries["caPassword0"] ?? entries["caPassword"],clientPKCS12:client,clientPassword:entries["clientPassword0"] ?? entries["clientPassword"])
    }
    static func parsePreferences(_ data:Data) throws ->[String:String] {
        let text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) ?? ""
        guard !text.isEmpty,text.range(of:"<!DOCTYPE",options:.caseInsensitive)==nil,text.range(of:"<!ENTITY",options:.caseInsensitive)==nil else {throw TAKCoT.Failure(message:"The package is not a plain TAK preference file")}
        let reader=TAKPreferenceReader(),parser=XMLParser(data:data)
        parser.shouldResolveExternalEntities=false;parser.delegate=reader
        guard parser.parse(),!reader.invalid else {throw TAKCoT.Failure(message:"Invalid TAK preference file")}
        return reader.values
    }
}
private final class TAKPreferenceReader:NSObject,XMLParserDelegate {
    var values:[String:String]=[:],invalid=false
    private var depth=0,key:String?,entryDepth:Int?,text=""
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        depth+=1
        guard depth<=64,values.count<2048 else {invalid=true;parser.abortParsing();return}
        if name=="entry" {
            guard key==nil else {invalid=true;parser.abortParsing();return}
            key=attributes["key"];entryDepth=depth;text=""
        }
    }
    func parser(_ parser:XMLParser,foundCharacters value:String) {
        guard key != nil else {return};text+=value
        if text.utf8.count>65536 {invalid=true;parser.abortParsing()}
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        if name=="entry",entryDepth==depth {
            if let key {
                let passwordKeys:Set<String>=["caPassword","caPassword0","clientPassword","clientPassword0"]
                values[key]=passwordKeys.contains(key) ? text:text.trimmingCharacters(in:.whitespacesAndNewlines)
            }
            key=nil;entryDepth=nil;text=""
        }
        depth-=1
    }
}
