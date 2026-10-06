import Foundation

/// Shared by the extension and its tests. No Photos/UIKit or global selection.
public enum PhotoSchedule {
    public struct Window {
        public let tick: Int64
        public let seed: UInt64
        public let nextDate: Date
    }

    public static func window(instanceID: String, sourceID: String, minutes: Int, now: Date) -> Window? {
        guard (5...10_080).contains(minutes), !instanceID.isEmpty else { return nil }
        let interval = Double(minutes) * 60
        let identity = hash(instanceID + "\u{0}" + sourceID)
        let phase = Double(identity % UInt64(minutes * 60))
        let tick = Int64(floor((now.timeIntervalSince1970 - phase) / interval))
        return Window(tick: tick, seed: identity ^ UInt64(bitPattern: tick),
                      nextDate: Date(timeIntervalSince1970: Double(tick + 1) * interval + phase))
    }

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

/// Index album sizes without materializing every photo ID. Space depends only
/// on the number of albums; resolving a random position uses binary search.
public struct PhotoBucketIndex {
    private let ends: [Int]
    public let total: Int

    public init?(counts: [Int]) {
        var total = 0, ends: [Int] = []
        for count in counts {
            guard count >= 0, count <= Int.max - total else { return nil }
            total += count
            ends.append(total)
        }
        self.ends = ends
        self.total = total
    }

    public func location(at position: Int) -> (bucket: Int, offset: Int)? {
        guard position >= 0, position < total else { return nil }
        var lower = 0, upper = ends.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ends[middle] <= position { lower = middle + 1 } else { upper = middle }
        }
        return (lower, position - (lower == 0 ? 0 : ends[lower - 1]))
    }
}

public enum PhotoFolderSampler {
    /// Probe only a few positions in an album-weighted source. Duplicate album
    /// membership must not make the last displayed asset appear again. If the
    /// random probes all hit that asset, two positions per album suffice to
    /// find another asset: PhotoKit does not duplicate assets inside an album.
    public static func select(counts: [Int], seed: UInt64, excluding previous: String?,
                              assetID: (Int, Int) -> String?) -> String? {
        guard let index = PhotoBucketIndex(counts: counts), index.total > 0 else { return nil }
        var fallback: String?
        func consider(_ bucket: Int, _ offset: Int) -> String? {
            guard let id = assetID(bucket, offset), !id.isEmpty else { return nil }
            if fallback == nil { fallback = id }
            return id == previous ? nil : id
        }
        // Generate positions directly rather than allocating/shuffling a range
        // with one integer per photo. A local PRNG keeps instances independent.
        var state = seed
        for _ in 0..<min(index.total, 16) {
            state &+= 0x9e3779b97f4a7c15
            var random = state
            random = (random ^ (random >> 30)) &* 0xbf58476d1ce4e5b9
            random = (random ^ (random >> 27)) &* 0x94d049bb133111eb
            random ^= random >> 31
            let position = Int(random % UInt64(index.total))
            let location = index.location(at: position)!
            if let id = consider(location.bucket, location.offset) { return id }
        }
        for (bucket, count) in counts.enumerated() {
            for offset in 0..<min(count, 2) {
                if let id = consider(bucket, offset) { return id }
            }
        }
        // A folder containing only the previous photo still has usable content.
        return fallback
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
