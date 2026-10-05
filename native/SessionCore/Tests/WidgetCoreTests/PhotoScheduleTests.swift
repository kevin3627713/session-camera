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
}
