import Foundation

// MARK: - MeetingDetectionResult

/// The result of a single detection pass performed by one detector.
public struct MeetingDetectionResult: Sendable {
    public let provider: MeetingProvider
    public let status: MeetingStatus
    public let timestamp: Date

    public init(
        provider: MeetingProvider,
        status: MeetingStatus,
        timestamp: Date = Date()
    ) {
        self.provider = provider
        self.status = status
        self.timestamp = timestamp
    }
}

// MARK: - MeetingDetectorProtocol

/// All meeting detectors must conform to this protocol.
/// Implementors are `AnyObject` (classes) so that `isEnabled` can be toggled
/// in-place through an existential without value-copy semantics.
public protocol MeetingDetectorProtocol: AnyObject, Sendable {
    /// The provider this detector is responsible for.
    var provider: MeetingProvider { get }

    /// Whether this detector is currently active.
    var isEnabled: Bool { get set }

    /// Synchronously inspects the local system state and returns a detection result.
    /// Must be safe to call on any thread without side-effects.
    func detect() -> MeetingDetectionResult
}
