import Foundation

/// Shared by the extension and its tests. No Photos/UIKit or global selection.
public enum PhotoSchedule {
    public struct Pick: Equatable {
        public let date: Date
        public let assetID: String
    }

    public static func plan(assetIDs: [String], instanceID: String, sourceID: String,
                            minutes: Int, now: Date, count: Int = 6) -> [Pick] {
        guard (5...10_080).contains(minutes), count > 0, !instanceID.isEmpty else { return [] }
        let assets = Array(Set(assetIDs)).sorted()
        guard !assets.isEmpty else { return [] }
        let interval = Double(minutes) * 60
        let identity = hash(instanceID + "\u{0}" + sourceID)
        let phase = Double(identity % UInt64(minutes * 60))
        let tick = Int64(floor((now.timeIntervalSince1970 - phase) / interval))
        return (0..<count).map { offset in
            let current = tick + Int64(offset)
            let date = offset == 0 ? now : Date(timeIntervalSince1970: Double(current) * interval + phase)
            return Pick(date: date, assetID: assets[index(tick: current, size: assets.count, seed: identity)])
        }
    }

    private static func index(tick: Int64, size: Int, seed: UInt64) -> Int {
        if size == 1 { return 0 }
        if size == 2 { return Int((UInt64(bitPattern: tick) &+ seed) & 1) }
        let round = Int64(floor(Double(tick) / Double(size)))
        let position = Int(tick - round * Int64(size))
        var order = shuffled(size: size, seed: seed ^ UInt64(bitPattern: round))
        if order[0] == shuffled(size: size, seed: seed ^ UInt64(bitPattern: round - 1)).last {
            order.swapAt(0, 1)
        }
        return order[position]
    }

    private static func shuffled(size: Int, seed: UInt64) -> [Int] {
        var state = seed
        var values = Array(0..<size)
        for index in stride(from: size - 1, through: 1, by: -1) {
            state &+= 0x9e3779b97f4a7c15
            var random = state
            random = (random ^ (random >> 30)) &* 0xbf58476d1ce4e5b9
            random = (random ^ (random >> 27)) &* 0x94d049bb133111eb
            random ^= random >> 31
            values.swapAt(index, Int(random % UInt64(index + 1)))
        }
        return values
    }

    private static func hash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

public enum PhotoFolderTraversal {
    /// Traverse nested folders once; albums reached through multiple paths
    /// stay unique. Used with actual PhotoKit identifiers by the extension.
    public static func albums(root: String, children: (String) -> [(id: String, folder: Bool)]) -> [String] {
        var seen = Set<String>(), albums = Set<String>(), pending = [root]
        while let folder = pending.popLast() {
            guard seen.insert(folder).inserted else { continue }
            for child in children(folder) {
                if child.folder { pending.append(child.id) }
                else { albums.insert(child.id) }
            }
        }
        return albums.sorted()
    }
}
