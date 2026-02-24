import Foundation
import os.log

/// Centralized structured logging for the BusyLight agent.
/// `@unchecked Sendable` is safe because OSLog is internally thread-safe.
public final class Logger: @unchecked Sendable {
    public enum LogCategory: String {
        case lifecycle = "com.busylight.agent.lifecycle"
        case ui = "com.busylight.agent.ui"
        case configuration = "com.busylight.agent.configuration"
        case device = "com.busylight.agent.device"
        case error = "com.busylight.agent.error"
        case calendar = "com.busylight.agent.calendar"
        case network = "com.busylight.agent.network"
        case meeting = "com.busylight.agent.meeting"
    }
    
    public enum LogLevel {
        case debug
        case info
        case warning
        case error
    }
    
    private let osLogCategory: OSLog
    
    public init(category: LogCategory) {
        self.osLogCategory = OSLog(subsystem: category.rawValue, category: category.rawValue)
    }
    
    public func log(_ message: String, level: LogLevel = .info) {
        let osLogType: OSLogType
        switch level {
        case .debug:
            osLogType = .debug
        case .info:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        }
        
        os_log("%{public}@", log: osLogCategory, type: osLogType, message)
    }
    
    public func logEvent(_ event: String, details: [String: String] = [:]) {
        var message = event
        if !details.isEmpty {
            let detailsString = details.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            message = "\(event) [\(detailsString)]"
        }
        log(message, level: .info)
    }
    
    public func logError(_ error: Error, context: String = "") {
        let errorMessage: String
        if !context.isEmpty {
            errorMessage = "\(context): \(error.localizedDescription)"
        } else {
            errorMessage = error.localizedDescription
        }
        log(errorMessage, level: .error)
    }
}

// Convenience loggers for different subsystems.
public let lifecycleLogger = Logger(category: .lifecycle)
public let uiLogger = Logger(category: .ui)
public let configLogger = Logger(category: .configuration)
public let deviceLogger = Logger(category: .device)
public let errorLogger = Logger(category: .error)
public let calendarLogger = Logger(category: .calendar)
public let networkLogger = Logger(category: .network)
public let meetingLogger = Logger(category: .meeting)

