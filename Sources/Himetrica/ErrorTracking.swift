import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Internal class that handles error tracking, including uncaught exceptions and signals
final class ErrorTracking {
    private let config: HimetricaConfig
    private let networkManager: NetworkManager
    private let storageManager: StorageManager

    // Rate limiting
    private var errorTimestamps: [TimeInterval] = []
    private let rateLimitLock = NSLock()

    // Deduplication
    private var sentErrorHashes = Set<String>()
    private let dedupLock = NSLock()
    private let dedupExpiry: TimeInterval = 5 * 60 // 5 minutes

    // Previous handlers (to restore on deinit)
    private var previousExceptionHandler: NSExceptionHandler?
    private typealias NSExceptionHandler = @convention(c) (NSException) -> Void

    // Device info for userAgent string
    private let userAgent: String

    // Current path provider
    private let currentPath: () -> String

    init(
        config: HimetricaConfig,
        networkManager: NetworkManager,
        storageManager: StorageManager,
        currentPath: @escaping () -> String
    ) {
        self.config = config
        self.networkManager = networkManager
        self.storageManager = storageManager
        self.currentPath = currentPath

        #if canImport(UIKit)
        let device = UIDevice.current
        self.userAgent = "Himetrica-iOS/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") (\(device.model); \(device.systemName) \(device.systemVersion))"
        #else
        self.userAgent = "Himetrica-macOS/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") (\(ProcessInfo.processInfo.operatingSystemVersionString))"
        #endif
    }

    // MARK: - Setup

    func setup() {
        guard config.captureUncaughtExceptions else { return }
        installExceptionHandler()
        installSignalHandlers()
    }

    // MARK: - Public Capture Methods

    func captureError(_ error: Error, context: [String: Any]?, severity: ErrorSeverity) {
        let nsError = error as NSError
        let message = error.localizedDescription
        let stack = Thread.callStackSymbols.joined(separator: "\n")

        sendErrorEvent(
            type: "error",
            message: message,
            stack: stack,
            source: nsError.domain,
            lineno: nil,
            colno: nil,
            severity: severity,
            context: context
        )
    }

    func captureMessage(_ message: String, severity: ErrorSeverity, context: [String: Any]?) {
        sendErrorEvent(
            type: "console",
            message: message,
            stack: nil,
            source: nil,
            lineno: nil,
            colno: nil,
            severity: severity,
            context: context
        )
    }

    func captureException(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")

        sendErrorEvent(
            type: "error",
            message: "\(exception.name.rawValue): \(exception.reason ?? "Unknown reason")",
            stack: stack,
            source: exception.name.rawValue,
            lineno: nil,
            colno: nil,
            severity: .error,
            context: exception.userInfo as? [String: Any]
        )
    }

    // MARK: - Rate Limiting

    private func isRateLimited() -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }

        let now = Date().timeIntervalSince1970
        let window = config.errorRateLimitWindow

        // Remove timestamps outside the window
        errorTimestamps.removeAll { $0 < now - window }

        if errorTimestamps.count >= config.errorRateLimit {
            return true
        }

        errorTimestamps.append(now)
        return false
    }

    // MARK: - Deduplication

    private func isDuplicate(hash: String) -> Bool {
        dedupLock.lock()
        defer { dedupLock.unlock() }

        if sentErrorHashes.contains(hash) {
            return true
        }

        sentErrorHashes.insert(hash)

        // Clean up after expiry
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + dedupExpiry) { [weak self] in
            self?.dedupLock.lock()
            self?.sentErrorHashes.remove(hash)
            self?.dedupLock.unlock()
        }

        return false
    }

    private func hashError(message: String, stack: String?, source: String?) -> String {
        let str = "\(message)|\(stack ?? "")|\(source ?? "")"
        var hash: Int = 0
        for char in str.utf8 {
            hash = ((hash << 5) &- hash) &+ Int(char)
        }
        return String(format: "%x", hash)
    }

    // MARK: - Send Error

    private func sendErrorEvent(
        type: String,
        message: String,
        stack: String?,
        source: String?,
        lineno: Int?,
        colno: Int?,
        severity: ErrorSeverity,
        context: [String: Any]?
    ) {
        let hash = hashError(message: message, stack: stack, source: source)

        if isRateLimited() {
            return
        }

        if isDuplicate(hash: hash) {
            return
        }

        // Normalize stack trace (limit to 20 lines)
        let normalizedStack = stack.map { trace -> String in
            let lines = trace.components(separatedBy: "\n").prefix(20)
            return lines.joined(separator: "\n")
        }

        let encodedContext: [String: AnyCodable]? = context?.mapValues { AnyCodable($0) }

        let event = ErrorEvent(
            visitorId: storageManager.getVisitorId(),
            sessionId: storageManager.getSessionId(timeout: config.sessionTimeout),
            type: type,
            message: message,
            stack: normalizedStack,
            source: source,
            lineno: lineno,
            colno: colno,
            severity: severity.rawValue,
            path: currentPath(),
            userAgent: userAgent,
            timestamp: Int(Date().timeIntervalSince1970 * 1000),
            context: encodedContext
        )

        networkManager.sendEvent(
            endpoint: "/api/track/errors?apiKey=\(config.apiKey)",
            data: event
        )
    }

    // MARK: - Exception Handler

    private func installExceptionHandler() {
        // Store previous handler to chain
        let previous = NSGetUncaughtExceptionHandler()

        NSSetUncaughtExceptionHandler { exception in
            // Use a static reference since this is a C function pointer
            ErrorTracking.handleUncaughtException(exception)
        }

        // Store previous handler in static storage for chaining
        ErrorTracking.previousHandler = previous
        ErrorTracking.sharedInstance = self
    }

    // Static storage for the C exception handler callback
    private static var sharedInstance: ErrorTracking?
    private static var previousHandler: (@convention(c) (NSException) -> Void)?

    private static func handleUncaughtException(_ exception: NSException) {
        sharedInstance?.captureException(exception)
        // Chain to previous handler
        previousHandler?(exception)
    }

    // MARK: - Signal Handlers

    private func installSignalHandlers() {
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig) { signalNumber in
                let message: String
                switch signalNumber {
                case SIGABRT: message = "Signal SIGABRT: Abort"
                case SIGSEGV: message = "Signal SIGSEGV: Segmentation fault"
                case SIGBUS:  message = "Signal SIGBUS: Bus error"
                case SIGFPE:  message = "Signal SIGFPE: Floating point exception"
                case SIGILL:  message = "Signal SIGILL: Illegal instruction"
                case SIGTRAP: message = "Signal SIGTRAP: Trace trap"
                default:      message = "Signal \(signalNumber): Unknown"
                }

                ErrorTracking.sharedInstance?.sendErrorEvent(
                    type: "error",
                    message: message,
                    stack: Thread.callStackSymbols.joined(separator: "\n"),
                    source: "signal",
                    lineno: nil,
                    colno: nil,
                    severity: .error,
                    context: ["signal": signalNumber]
                )

                // Re-raise the signal with default handler
                Foundation.signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }
}
