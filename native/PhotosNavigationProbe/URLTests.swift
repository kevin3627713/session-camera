import Foundation

@main struct ProbeURLTests {
    static func main() throws {
        let photo = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let album = "FEDCBA98-7654-3210-FEDC-BA9876543210"
        let cloud = "A+/ B&?=中文%suffix"
        let ids = ProbeIdentifiers(assetLocalID: photo + "/L0/001", albumLocalID: album + "/L0/040",
                                   albumName: "旅途 & Family/2026", assetCloudID: cloud,
                                   albumCloudID: "album+cloud/complete", mappingNotes: [])
        let candidates = ProbeCandidate.all(ids)
        func values(_ id: String) throws -> [String: String] {
            let url = try XCTUnwrap(candidates.first { $0.id == id }?.url)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }
        let a = try values("A")
        precondition(a["cloud-identifier"] == cloud, "Cloud identifiers must survive reserved characters intact")
        let c = try values("C")
        precondition(c["uuid"] == photo && c["albumuuid"] == album, "Internal asset route needs both correct UUIDs")
        let d = try values("D")
        precondition(d["uuid"] == album && d["revealassetuuid"] == photo, "Album and asset roles must not be swapped")
        let e = try values("E"), k = try values("K")
        precondition(e["identifier"] == photo + "/L0/001", "The complete local identifier must not be truncated")
        precondition(k["name"] == ids.albumName, "Album names must survive spaces, slashes and ampersands")
        precondition(ProbeIdentifiers.uuid(from: "not-a-uuid/L0/001") == nil, "Never fabricate a UUID")
        let noCloud = ProbeIdentifiers(assetLocalID: ids.assetLocalID, albumLocalID: ids.albumLocalID, albumName: ids.albumName,
                                       assetCloudID: nil, albumCloudID: nil, mappingNotes: [])
        let missing = ProbeCandidate.all(noCloud)
        precondition(missing.first { $0.id == "A" }?.url == nil && missing.first { $0.id == "B" }?.url == nil,
                     "Unavailable cloud mappings must disable cloud routes")
        precondition(missing.first { $0.id == "C" }?.url != nil, "UUID routes remain testable without a cloud mapping")
        precondition(!ProbeCandidate.permitted(URL(string: "https://example.com/asset")!) &&
                     !ProbeCandidate.permitted(URL(string: "photos-navigation:")!) &&
                     ProbeCandidate.permitted(URL(string: "photos://asset?uuid=" + photo)!), "Custom URL bounds must hold")
        print("9 focused URL checks passed: complete identifiers, encoding, role assignment, missing mappings and route bounds")
    }
    static func XCTUnwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "ProbeURLTests", code: 1) }
        return value
    }
}
