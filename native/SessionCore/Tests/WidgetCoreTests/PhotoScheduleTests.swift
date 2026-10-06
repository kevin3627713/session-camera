import Foundation
import XCTest
@testable import WidgetCore

final class PhotoScheduleTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_791_200_000)
    private let assets = (0..<11).map { "photo-\($0)" }
    func testInstancesKeepIndependentSequencesAndPhases() {
        let a = PhotoSchedule.plan(assetIDs: assets, instanceID: "widget-A", sourceID: "album", minutes: 15, now: date, count: 20)
        let b = PhotoSchedule.plan(assetIDs: assets, instanceID: "widget-B", sourceID: "album", minutes: 15, now: date, count: 20)
        XCTAssertNotEqual(a.map(\.assetID), b.map(\.assetID))
        XCTAssertNotEqual(a[1].date, b[1].date)
        XCTAssertEqual(a, PhotoSchedule.plan(assetIDs: assets, instanceID: "widget-A", sourceID: "album", minutes: 15, now: date, count: 20))
    }
    func testReloadDuringSamePeriodKeepsDisplayedPhoto() {
        let first = PhotoSchedule.plan(assetIDs: assets, instanceID: "A", sourceID: "album", minutes: 60, now: date)
        let second = PhotoSchedule.plan(assetIDs: Array(assets.reversed()), instanceID: "A", sourceID: "album", minutes: 60, now: date.addingTimeInterval(1))
        XCTAssertEqual(first[0].assetID, second[0].assetID)
        XCTAssertEqual(first[1], second[1])
    }
    func testNoAdjacentRepeatsIncludingShuffleBoundaries() {
        for size in 2...15 {
            let values = PhotoSchedule.plan(assetIDs: Array(assets.prefix(min(size, 11))), instanceID: "A", sourceID: "album", minutes: 5, now: date, count: 100)
            for pair in zip(values, values.dropFirst()) { XCTAssertNotEqual(pair.0.assetID, pair.1.assetID) }
        }
    }
    func testIntervalsAndSourceMembership() {
        let values = PhotoSchedule.plan(assetIDs: assets, instanceID: "A", sourceID: "folder", minutes: 37, now: date)
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(values[0].date, date)
        for value in values { XCTAssertTrue(assets.contains(value.assetID)) }
        for pair in zip(values.dropFirst(), values.dropFirst(2)) { XCTAssertEqual(pair.1.date.timeIntervalSince(pair.0.date), 37 * 60) }
    }
    func testEmptyInvalidAndSinglePhotoSources() {
        XCTAssertTrue(PhotoSchedule.plan(assetIDs: [], instanceID: "A", sourceID: "", minutes: 5, now: date).isEmpty)
        for minutes in [0, 4, 10_081] {
            XCTAssertTrue(PhotoSchedule.plan(assetIDs: assets, instanceID: "A", sourceID: "", minutes: minutes, now: date).isEmpty)
        }
        XCTAssertTrue(PhotoSchedule.plan(assetIDs: assets, instanceID: "", sourceID: "", minutes: 5, now: date).isEmpty)
        XCTAssertEqual(Set(PhotoSchedule.plan(assetIDs: ["only", "only"], instanceID: "A", sourceID: "album", minutes: 5, now: date).map(\.assetID)), ["only"])
    }
    func testNestedFoldersDeduplicateAndRejectCycles() {
        let graph: [String: [(String, Bool)]] = ["root": [("A", false), ("child", true)], "child": [("B", false), ("A", false), ("root", true)]]
        XCTAssertEqual(PhotoFolderTraversal.albums(root: "root") { graph[$0] ?? [] }, ["A", "B"])
        XCTAssertTrue(PhotoFolderTraversal.albums(root: "missing") { graph[$0] ?? [] }.isEmpty)
    }

    func testFolderIndexSkipsEmptyAlbumsAndRejectsInvalidCounts() {
        let index = PhotoBucketIndex(counts: [0, 3, 0, 7])!
        XCTAssertEqual(index.total, 10)
        XCTAssertEqual(index.location(at: 0)?.bucket, 1)
        XCTAssertEqual(index.location(at: 2)?.offset, 2)
        XCTAssertEqual(index.location(at: 3)?.bucket, 3)
        XCTAssertEqual(index.location(at: 9)?.offset, 6)
        XCTAssertNil(index.location(at: -1))
        XCTAssertNil(index.location(at: 10))
        XCTAssertNil(PhotoBucketIndex(counts: [-1]))
        XCTAssertNil(PhotoBucketIndex(counts: [Int.max, 1]))
    }

    func testVeryLargeFolderReadsOneCandidateWithoutEnumeratingItsPhotos() {
        var reads = 0
        let counts = [25_000_000, 35_000_000]
        let selected = PhotoFolderSampler.select(counts: counts, seed: 42, excluding: nil) { bucket, offset in
            reads += 1
            XCTAssertTrue((0..<counts[bucket]).contains(offset))
            return "\(bucket):\(offset)"
        }
        XCTAssertNotNil(selected)
        XCTAssertEqual(reads, 1)
    }

    func testFolderSamplerWeightsAlbumsByPhotoCountAndKeepsSeedStable() {
        let counts = [10, 90]
        func selection(_ seed: UInt64) -> String? {
            PhotoFolderSampler.select(counts: counts, seed: seed, excluding: nil) { bucket, offset in "\(bucket):\(offset)" }
        }
        XCTAssertEqual(selection(42), selection(42))
        let selections = (0..<1000).compactMap { selection(UInt64($0)) }
        let largeAlbum = selections.filter { $0.hasPrefix("1:") }.count
        XCTAssertTrue((850...950).contains(largeAlbum))
        XCTAssertGreaterThan(Set(selections).count, 90)
    }

    func testDuplicateAlbumMembershipCannotForceAnAdjacentRepeat() {
        // Every random position aliases the previous photo. A second unique
        // asset exists only in the final album and is reached by bounded probes.
        let counts = [Int](repeating: 1_000_000, count: 20)
        var reads = 0
        let selected = PhotoFolderSampler.select(counts: counts, seed: 42, excluding: "previous") { bucket, offset in
            reads += 1
            return bucket == 19 && offset == 1 ? "different" : "previous"
        }
        XCTAssertEqual(selected, "different")
        XCTAssertLessThanOrEqual(reads, 16 + 2 * counts.count)
    }

    func testFolderSamplerHandlesOneUniquePhotoAndUnavailableCandidates() {
        XCTAssertEqual(PhotoFolderSampler.select(counts: [1, 1], seed: 7, excluding: "only") { _, _ in "only" }, "only")
        XCTAssertNil(PhotoFolderSampler.select(counts: [0, 0], seed: 7, excluding: nil) { _, _ in XCTFail(); return nil })
        XCTAssertNil(PhotoFolderSampler.select(counts: [4], seed: 7, excluding: nil) { _, _ in nil })
    }

    func testFolderWindowUsesExistingInstanceSchedule() {
        let window = PhotoSchedule.window(instanceID: "A", sourceID: "folder", minutes: 37, now: date)!
        let old = PhotoSchedule.plan(assetIDs: assets, instanceID: "A", sourceID: "folder", minutes: 37, now: date)
        XCTAssertEqual(window.nextDate, old[1].date)
        XCTAssertEqual(window.seed, PhotoSchedule.window(instanceID: "A", sourceID: "folder", minutes: 37, now: date.addingTimeInterval(1))?.seed)
        XCTAssertNotEqual(window.seed, PhotoSchedule.window(instanceID: "B", sourceID: "folder", minutes: 37, now: date)?.seed)
    }
}
