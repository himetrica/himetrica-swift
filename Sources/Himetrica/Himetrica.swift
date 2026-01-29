import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// The main Himetrica analytics SDK class
@MainActor
public final class Himetrica: ObservableObject {
    /// The shared singleton instance
    private static var _shared: Himetrica?
    public static var shared: Himetrica {
        guard let instance = _shared else {
            fatalError("Himetrica.configure() must be called before accessing shared instance")
        }
        return instance
    }

    private static var isConfigured = false

    private let config: HimetricaConfig
    private let storageManager: StorageManager
    private let networkManager: NetworkManager
    private var errorTracking: ErrorTracking?

    // Screen tracking state
    private var currentScreenId: String?
    private var currentScreenName: String?
    private var screenStartTime: Date?

    // Device info (cached)
    private let deviceInfo: DeviceInfo

    private init(config: HimetricaConfig) {
        self.config = config
        self.storageManager = StorageManager()
        self.networkManager = NetworkManager(config: config, storageManager: storageManager)
        self.deviceInfo = DeviceInfo()

        setupAppLifecycleObservers()
        setupErrorTracking()
        log("Initialized with API URL: \(config.apiUrl)")
    }

    // MARK: - Configuration

    /// Configures the Himetrica SDK with the provided configuration
    /// - Parameter config: The configuration options
    @MainActor
    public static func configure(with config: HimetricaConfig) {
        guard !isConfigured else {
            print("[Himetrica] Warning: SDK already configured")
            return
        }

        _shared = Himetrica(config: config)
        isConfigured = true
    }

    /// Configures the Himetrica SDK with just an API key
    /// - Parameter apiKey: The API key for your Himetrica project
    @MainActor
    public static func configure(apiKey: String) {
        configure(with: HimetricaConfig(apiKey: apiKey))
    }

    // MARK: - Screen Tracking

    /// Tracks a screen view
    /// - Parameters:
    ///   - name: The name of the screen
    ///   - properties: Optional additional properties
    public func trackScreen(name: String, properties: [String: Any]? = nil) {
        // Check tracking permission if configured
        if config.respectAdTracking && !isTrackingAllowed() {
            log("Tracking disabled by user preference")
            return
        }

        // Send duration for previous screen
        sendScreenDuration()

        // Start tracking new screen
        currentScreenId = UUID().uuidString
        currentScreenName = name
        screenStartTime = Date()

        let event = ScreenViewEvent(
            visitorId: storageManager.getVisitorId(),
            sessionId: storageManager.getSessionId(timeout: config.sessionTimeout),
            pageViewId: currentScreenId!,
            path: "/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            title: name,
            referrer: storageManager.getOriginalReferrer(),
            queryString: "",
            screenWidth: deviceInfo.screenWidth,
            screenHeight: deviceInfo.screenHeight,
            platform: "ios",
            appVersion: deviceInfo.appVersion,
            osVersion: deviceInfo.osVersion,
            deviceModel: deviceInfo.deviceModel,
            locale: deviceInfo.locale
        )

        networkManager.sendEvent(endpoint: "/api/track/event", data: event)
        log("Tracked screen: \(name)")
    }

    /// Sends the duration for the current screen
    private func sendScreenDuration() {
        guard let screenId = currentScreenId,
              let startTime = screenStartTime else {
            return
        }

        let duration = Int(Date().timeIntervalSince(startTime))

        // Only send if duration is reasonable (1 second to 1 hour)
        guard duration >= 1 && duration <= 3600 else {
            log("Duration out of range: \(duration)s")
            return
        }

        let event = DurationEvent(pageViewId: screenId, duration: duration)

        if let data = try? JSONEncoder().encode(event) {
            networkManager.sendBeacon(
                endpoint: "/api/track/beacon?apiKey=\(config.apiKey)",
                data: data
            )
        }

        currentScreenId = nil
        screenStartTime = nil
        log("Sent duration: \(duration)s for screen")
    }

    // MARK: - Custom Events

    /// Tracks a custom event
    /// - Parameters:
    ///   - name: The event name (must start with a letter, alphanumeric + underscore/hyphen)
    ///   - properties: Optional event properties
    public func track(_ name: String, properties: [String: Any]? = nil) {
        // Validate event name
        guard isValidEventName(name) else {
            log("Invalid event name: \(name)")
            return
        }

        if config.respectAdTracking && !isTrackingAllowed() {
            log("Tracking disabled by user preference")
            return
        }

        let encodedProperties: [String: AnyCodable]? = properties?.mapValues { AnyCodable($0) }

        let event = CustomEvent(
            visitorId: storageManager.getVisitorId(),
            sessionId: storageManager.getSessionId(timeout: config.sessionTimeout),
            eventName: name,
            properties: encodedProperties,
            path: currentScreenName.map { "/\($0.lowercased().replacingOccurrences(of: " ", with: "-"))" } ?? "",
            title: currentScreenName ?? "",
            queryString: "",
            platform: "ios"
        )

        networkManager.sendEvent(endpoint: "/api/track/custom-event", data: event)
        log("Tracked event: \(name)")
    }

    // MARK: - User Identification

    /// Identifies the current visitor with additional information
    /// - Parameters:
    ///   - name: The user's name
    ///   - email: The user's email
    ///   - metadata: Additional custom metadata
    public func identify(name: String? = nil, email: String? = nil, metadata: [String: Any]? = nil) {
        let encodedMetadata: [String: AnyCodable]? = metadata?.mapValues { AnyCodable($0) }

        let event = IdentifyEvent(
            visitorId: storageManager.getVisitorId(),
            name: name,
            email: email,
            metadata: encodedMetadata
        )

        networkManager.sendEvent(endpoint: "/api/track/identify", data: event)
        log("Identified user: \(name ?? "unknown")")
    }

    // MARK: - Deep Link Attribution

    /// Sets the referrer from a deep link or universal link
    /// - Parameter url: The URL that opened the app
    public func setReferrer(from url: URL) {
        let referrer = url.absoluteString
        storageManager.setOriginalReferrer(referrer)
        log("Set referrer: \(referrer)")
    }

    // MARK: - App Lifecycle

    /// Handles scene phase changes (call this from your App's onChange)
    /// - Parameter phase: The new scene phase
    public func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            storageManager.updateSessionTimestamp()
            networkManager.flush()
        case .inactive, .background:
            sendScreenDuration()
        @unknown default:
            break
        }
    }

    // MARK: - Utility

    /// Returns the current visitor ID
    public var visitorId: String {
        storageManager.getVisitorId()
    }

    /// Flushes any queued events
    public func flush() {
        networkManager.flush()
    }

    /// Resets all stored data (visitor ID, session, queue)
    public func reset() {
        sendScreenDuration()
        storageManager.reset()
        log("All data reset")
    }

    // MARK: - Error Tracking

    /// Captures an error and sends it to Himetrica
    /// - Parameters:
    ///   - error: The error to capture
    ///   - context: Optional additional context
    public func captureError(_ error: Error, context: [String: Any]? = nil) {
        errorTracking?.captureError(error, context: context, severity: .error)
        log("Captured error: \(error.localizedDescription)")
    }

    /// Captures a message and sends it to Himetrica
    /// - Parameters:
    ///   - message: The message to capture
    ///   - severity: The severity level (defaults to .info)
    ///   - context: Optional additional context
    public func captureMessage(_ message: String, severity: ErrorSeverity = .info, context: [String: Any]? = nil) {
        errorTracking?.captureMessage(message, severity: severity, context: context)
        log("Captured message: \(message)")
    }

    private func setupErrorTracking() {
        let tracker = ErrorTracking(
            config: config,
            networkManager: networkManager,
            storageManager: storageManager,
            currentPath: { [weak self] in
                self?.currentScreenName.map { "/\($0.lowercased().replacingOccurrences(of: " ", with: "-"))" } ?? ""
            }
        )
        tracker.setup()
        self.errorTracking = tracker
    }

    // MARK: - Private Helpers

    private func isValidEventName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9_-]*$")
        let range = NSRange(name.startIndex..., in: name)
        return regex?.firstMatch(in: name, range: range) != nil
    }

    private func isTrackingAllowed() -> Bool {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized ||
                   ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        }
        #endif
        return true
    }

    private func setupAppLifecycleObservers() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendScreenDuration()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendScreenDuration()
            }
        }
        #endif
    }

    private func log(_ message: String) {
        guard config.enableLogging else { return }
        print("[Himetrica] \(message)")
    }
}

// MARK: - Device Info

private struct DeviceInfo {
    let screenWidth: Int
    let screenHeight: Int
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let locale: String

    init() {
        #if canImport(UIKit)
        let screen = UIScreen.main
        self.screenWidth = Int(screen.bounds.width * screen.scale)
        self.screenHeight = Int(screen.bounds.height * screen.scale)
        self.osVersion = UIDevice.current.systemVersion
        self.deviceModel = UIDevice.current.model
        #else
        self.screenWidth = 0
        self.screenHeight = 0
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = "Mac"
        #endif

        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        self.locale = Locale.current.identifier
    }
}
