import Foundation
import EventKit

// MARK: - Protocol for testability

/// Abstraction over calendar permission handling injected into `CalendarEngine`.
@MainActor
public protocol CalendarPermissionManaging: AnyObject {
    /// Requests calendar access.
    /// - Returns: `true` when access is granted.
    /// - Throws: `CalendarPermissionManager.PermissionError` on failure.
    @discardableResult
    func requestAccess() async throws -> Bool
}

// MARK: - Concrete implementation

/// Handles EventKit calendar permission requests and status reporting.
///
/// All methods are isolated to `@MainActor` because `EKEventStore` must be
/// accessed from a consistent thread.  This matches the `ConfigurationManager`
/// pattern used elsewhere in the project.
@MainActor
public final class CalendarPermissionManager: CalendarPermissionManaging {

    // MARK: - Types

    /// Simplified view of the system's `EKAuthorizationStatus` for this engine.
    public enum PermissionStatus: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
        case unknown
    }

    /// Errors that can be thrown by `requestAccess()`.
    public enum PermissionError: Error, LocalizedError, Sendable {
        case denied
        case restricted
        case unknown

        public var errorDescription: String? {
            switch self {
            case .denied:
                return "Calendar access was denied by the user. " +
                       "Open System Settings › Privacy & Security › Calendars to grant access."
            case .restricted:
                return "Calendar access is restricted by device policy."
            case .unknown:
                return "Calendar access status could not be determined."
            }
        }
    }

    // MARK: - Properties

    private let store: EKEventStore
    private let logger: Logger

    // MARK: - Init

    public init(store: EKEventStore = EKEventStore(), logger: Logger = calendarLogger) {
        self.store = store
        self.logger = logger
    }

    // MARK: - Public API

    /// The current authorization status without triggering a permission prompt.
    public var currentStatus: PermissionStatus {
        mapStatus(EKEventStore.authorizationStatus(for: .event))
    }

    /// Requests calendar access if not yet determined.  Returns `true` when
    /// access is (or was already) granted.
    ///
    /// - Throws: `PermissionError` when access is denied or restricted.
    @discardableResult
    public func requestAccess() async throws -> Bool {
        logger.logEvent("calendar.permission.request",
                        details: ["current_status": currentStatus.debugDescription])

        let existing = EKEventStore.authorizationStatus(for: .event)

        // macOS 14+ fast paths.
        if existing == .fullAccess {
            logger.logEvent("calendar.permission.result", details: ["status": "already_authorized"])
            return true
        }
        // .writeOnly means we can create but not read events — insufficient.
        if existing == .writeOnly {
            logger.logEvent("calendar.permission.result", details: ["status": "write_only_insufficient"])
            throw PermissionError.denied
        }

        // Fast paths – no prompt needed.
        switch existing {
        case .authorized:
            logger.logEvent("calendar.permission.result", details: ["status": "already_authorized"])
            return true
        case .denied:
            logger.logEvent("calendar.permission.result", details: ["status": "denied"])
            throw PermissionError.denied
        case .restricted:
            logger.logEvent("calendar.permission.result", details: ["status": "restricted"])
            throw PermissionError.restricted
        case .notDetermined:
            break   // will prompt below
        case .fullAccess, .writeOnly:
            break   // handled above
        @unknown default:
            break
        }

        // Present the system permission prompt using the macOS 14+ async API.
        do {
            try await store.requestFullAccessToEvents()
            logger.logEvent("calendar.permission.result", details: ["status": "granted"])
            return true

        } catch let permError as PermissionError {
            throw permError
        } catch let nsError as NSError where nsError.domain == EKErrorDomain {
            switch nsError.code {
            case EKError.Code.eventStoreNotAuthorized.rawValue:
                logger.logEvent("calendar.permission.result", details: ["status": "denied"])
                throw PermissionError.denied
            default:
                logger.logError(nsError, context: "calendar.permission.request")
                throw PermissionError.unknown
            }
        } catch {
            logger.logError(error, context: "calendar.permission.request")
            throw PermissionError.unknown
        }
    }

    // MARK: - Helpers

    private func mapStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:  return .notDetermined
        case .authorized:     return .authorized
        case .denied:         return .denied
        case .restricted:     return .restricted
        case .fullAccess:     return .authorized
        case .writeOnly:      return .unknown   // write-only is insufficient for reading
        @unknown default:     return .unknown
        }
    }
}

// MARK: - PermissionStatus debug description

extension CalendarPermissionManager.PermissionStatus: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .unknown:       return "unknown"
        }
    }
}
