import Foundation

/// CoT XML events may share a socket read or split inside a UTF-8 character.
/// Frame bytes first and decode only complete events. Comments, CDATA and quoted
/// '>' characters cannot terminate a frame. No XML entities are expanded here.
public struct TAKCoTStream: Sendable {
    public enum Failure:Error,Equatable {case bufferLimit,invalidUTF8,invalidXMLFraming}
    private var bytes:[UInt8]=[]
    private var declarationTail:[UInt8]=[]
    public let maximumBytes:Int
    public init(maximumBytes:Int=1_000_000) {self.maximumBytes=max(1024,min(4_000_000,maximumBytes))}
    public var bufferedBytes:Int {bytes.count}
    public mutating func clear() {bytes.removeAll(keepingCapacity:true);declarationTail.removeAll(keepingCapacity:true)}
    public mutating func feed(_ data:Data) throws ->[String] {
        guard data.count<=maximumBytes,bytes.count<=maximumBytes-data.count else {clear();throw Failure.bufferLimit}
        // Reject hostile declarations even when they precede the event and
        // split across socket reads; trimming prelude noise must not hide them.
        let scanned=Data((declarationTail+data).map { (97...122).contains($0) ? $0-32:$0 })
        if scanned.range(of:Data("<!DOCTYPE".utf8)) != nil || scanned.range(of:Data("<!ENTITY".utf8)) != nil {
            clear();throw Failure.invalidXMLFraming
        }
        declarationTail=Array(scanned.suffix(8))
        bytes.append(contentsOf:data)
        var output:[String]=[]
        while true {
            var search=0,begin:Int?
            while let index=find(Array("<event".utf8),from:search) {
                if index+6==bytes.count {if index>0 {bytes.removeFirst(index)};return output}
                if [9,10,13,32,47,62].contains(bytes[index+6]) {begin=index;break}
                search=index+1
            }
            guard let begin else {if bytes.count>5 {bytes.removeFirst(bytes.count-5)};return output}
            if begin>0 {bytes.removeFirst(begin)}
            let nextEnd:Int?
            do {nextEnd=try frameEnd()} catch {clear();throw error}
            guard let end=nextEnd else {return output}
            let frame=Data(bytes[0..<end]);bytes.removeFirst(end)
            guard let text=String(data:frame,encoding:.utf8) else {clear();throw Failure.invalidUTF8}
            output.append(text)
        }
    }
    private func find(_ token:[UInt8],from start:Int)->Int? {
        guard start>=0,bytes.count>=token.count,start<=bytes.count-token.count else {return nil}
        for i in start...(bytes.count-token.count) where bytes[i]==token[0] {
            if bytes[i..<(i+token.count)].elementsEqual(token) {return i}
        }
        return nil
    }
    private func has(_ token:String,at index:Int)->Bool {
        let expected=Array(token.utf8)
        return index+expected.count<=bytes.count && bytes[index..<(index+expected.count)].elementsEqual(expected)
    }
    private func frameEnd() throws ->Int? {
        var cursor=0,depth=0
        while let start=find([60],from:cursor) {
            if has("<!--",at:start) {guard let end=find(Array("-->".utf8),from:start+4) else {return nil};cursor=end+3;continue}
            if has("<![CDATA[",at:start) {guard let end=find(Array("]]>".utf8),from:start+9) else {return nil};cursor=end+3;continue}
            if has("<?",at:start) {guard let end=find([63,62],from:start+2) else {return nil};cursor=end+2;continue}
            guard start+1<bytes.count else {return nil}
            if bytes[start+1]==33 {
                // A split comment/CDATA prefix needs more bytes, not a new frame.
                if bytes.count-start<9 {return nil}
                throw Failure.invalidXMLFraming
            }
            var quote:UInt8?,end:Int?,index=start+1
            while index<bytes.count {
                let byte=bytes[index]
                if let current=quote {if byte==current {quote=nil}}
                else if byte==34 || byte==39 {quote=byte}
                else if byte==62 {end=index;break}
                index+=1
            }
            guard let end else {return nil}
            if bytes[start+1]==47 {depth-=1}
            else if end==start || bytes[end-1] != 47 {depth+=1}
            guard depth>=0,depth<=64 else {throw Failure.invalidXMLFraming}
            if depth==0 {return end+1}
            cursor=end+1
        }
        return nil
    }
}
