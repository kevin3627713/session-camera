import Foundation

/// Never persisted. Callbacks carry the ticket issued when capture/edit began.
public struct CaptureTicket: Equatable, Hashable {
    public let sessionID: UUID
    public let captureID: UUID

    public init(sessionID: UUID, captureID: UUID = UUID()) {
        self.sessionID = sessionID
        self.captureID = captureID
    }
}

public struct SessionLedger {
    public private(set) var sessionID = UUID()
    private var captureIDs = Set<UUID>()

    public init() {}

    public func issueTicket() -> CaptureTicket {
        CaptureTicket(sessionID: sessionID)
    }

    @discardableResult
    public mutating func admit(_ ticket: CaptureTicket) -> Bool {
        guard ticket.sessionID == sessionID else { return false }
        return captureIDs.insert(ticket.captureID).inserted
    }

    public func contains(_ ticket: CaptureTicket) -> Bool {
        ticket.sessionID == sessionID && captureIDs.contains(ticket.captureID)
    }

    public mutating func remove(_ ticket: CaptureTicket) {
        guard ticket.sessionID == sessionID else { return }
        captureIDs.remove(ticket.captureID)
    }

    public mutating func reset() {
        sessionID = UUID()
        captureIDs.removeAll()
    }
}
