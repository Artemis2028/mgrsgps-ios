import Foundation

/// Read-only remote data, never implicitly merged into saved waypoints. A busy
/// server cannot grow this scene without bound or revive a contact after a clock
/// rollback. The app supplies both wall time and system uptime at receipt.
public struct TAKRemoteScene:Sendable {
    public static let maximumItems=1000
    private struct Entry:Sendable {let item:TAKRemoteItem;let receivedUptime:TimeInterval;let expiresUptime:TimeInterval}
    private var order:[String]=[]
    private var values:[String:Entry]=[:]
    public init() {}
    public var items:[TAKRemoteItem] {order.compactMap {values[$0]?.item}}
    public mutating func clear() {order.removeAll();values.removeAll()}
    @discardableResult public mutating func expire(now:Date,uptime:TimeInterval)->Bool {
        guard now.timeIntervalSince1970.isFinite,uptime.isFinite else {let hadItems = !values.isEmpty;clear();return hadItems}
        let expired=values.filter {uptime<$0.value.receivedUptime || uptime>=$0.value.expiresUptime || now>=$0.value.item.staleAt}.map(\.key)
        guard !expired.isEmpty else {return false}
        for id in expired {values[id]=nil};order.removeAll {values[$0]==nil};return true
    }
    @discardableResult public mutating func apply(_ event:TAKEvent,now:Date,uptime:TimeInterval)->Bool {
        guard now.timeIntervalSince1970.isFinite,uptime.isFinite else {return false}
        let expired=expire(now:now,uptime:uptime)
        switch event {
        case .other:return expired
        case .delete(let id):
            guard values.removeValue(forKey:id) != nil else {return expired}
            order.removeAll {$0==id};return true
        case .item(let item):
            guard item.staleAt>now,!item.id.isEmpty,item.id.utf16.count<=512,
                  !item.points.isEmpty,item.points.count<=TAKCoT.maximumVertices,item.points.allSatisfy(TAKCoT.validPosition),
                  !item.closed || item.points.count>=3 else {return expired}
            guard values[item.id] != nil || values.count<Self.maximumItems else {return expired}
            if values[item.id]==nil {order.append(item.id)}
            values[item.id]=Entry(item:item,receivedUptime:uptime,expiresUptime:uptime+min(TAKCoT.maximumStaleSeconds,item.staleAt.timeIntervalSince(now)))
            return true
        }
    }
}
