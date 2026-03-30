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
    private var backgroundAt: Date?
    private var tapCount: Int = 0

    // Device info (cached)
    private let deviceInfo: DeviceInfo

    private init(config: HimetricaConfig) {
        self.config = config
        self.storageManager = StorageManager()
        self.deviceInfo = DeviceInfo()
        let ua = "Himetrica-iOS/\(deviceInfo.appVersion) (\(deviceInfo.deviceModel); iOS \(deviceInfo.osVersion))"
        self.networkManager = NetworkManager(config: config, storageManager: storageManager, userAgent: ua)

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
        tapCount = 0

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
    private func sendHeartbeat() {
        let payload = HeartbeatEvent(
            visitorId: storageManager.getVisitorId(),
            sessionId: storageManager.getSessionId(timeout: config.sessionTimeout)
        )

        if let data = try? JSONEncoder().encode(payload) {
            networkManager.sendBeacon(
                endpoint: "/api/track/heartbeat?apiKey=\(config.apiKey)",
                data: data
            )
        }
        log("Heartbeat sent")
    }

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

        let event = DurationEvent(pageViewId: screenId, duration: duration, clickCount: tapCount > 0 ? tapCount : nil)

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

    // MARK: - Tap Tracking

    /// Tracks a user tap/press. Call this from your UI to count interactions per screen.
    public func trackTap() {
        tapCount += 1
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
    ///   - userId: A stable external user ID for cross-device identification
    ///   - name: The user's name
    ///   - email: The user's email
    ///   - metadata: Additional custom metadata
    public func identify(userId: String? = nil, name: String? = nil, email: String? = nil, metadata: [String: Any]? = nil) {
        let encodedMetadata: [String: AnyCodable]? = metadata?.mapValues { AnyCodable($0) }

        let event = IdentifyEvent(
            visitorId: storageManager.getVisitorId(),
            userId: userId,
            name: name,
            email: email,
            metadata: encodedMetadata
        )

        networkManager.sendEvent(endpoint: "/api/track/identify", data: event)
        log("Identified user: \(userId ?? name ?? "unknown")")
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
            // When iOS kills the app in the background, backgroundAt is nil on relaunch.
            // Use stored session timestamp to determine the real gap.
            let awaySeconds: TimeInterval
            if let bg = backgroundAt {
                awaySeconds = Date().timeIntervalSince(bg)
            } else {
                awaySeconds = storageManager.timeSinceLastSessionActivity() ?? config.sessionTimeout
            }
            backgroundAt = nil

            if awaySeconds >= config.sessionTimeout {
                // Session expired — create new session and re-track current screen
                _ = storageManager.getSessionId(timeout: config.sessionTimeout)
                if let name = currentScreenName {
                    trackScreen(name: name)
                }
            } else if awaySeconds > 5 * 60 {
                // Away 5+ min but session still valid — lightweight heartbeat
                storageManager.updateSessionTimestamp()
                sendHeartbeat()
            } else {
                storageManager.updateSessionTimestamp()
            }
            networkManager.flush()
        case .inactive, .background:
            sendScreenDuration()
            backgroundAt = Date()
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
        self.errorTracking = ErrorTracking(
            config: config,
            networkManager: networkManager,
            storageManager: storageManager,
            currentPath: { [weak self] in
                self?.currentScreenName.map { "/\($0.lowercased().replacingOccurrences(of: " ", with: "-"))" } ?? ""
            }
        )
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
                self?.backgroundAt = Date()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                // When iOS kills the app in the background, backgroundAt is nil on relaunch.
                // In that case, check the stored session timestamp to determine the real gap.
                let awaySeconds: TimeInterval
                if let bg = self.backgroundAt {
                    awaySeconds = Date().timeIntervalSince(bg)
                } else {
                    // App was killed — use stored session timestamp to calculate gap
                    awaySeconds = self.storageManager.timeSinceLastSessionActivity() ?? self.config.sessionTimeout
                }
                self.backgroundAt = nil

                if awaySeconds >= self.config.sessionTimeout {
                    _ = self.storageManager.getSessionId(timeout: self.config.sessionTimeout)
                    if let name = self.currentScreenName {
                        self.trackScreen(name: name)
                    }
                } else if awaySeconds > 5 * 60 {
                    self.storageManager.updateSessionTimestamp()
                    self.sendHeartbeat()
                } else {
                    self.storageManager.updateSessionTimestamp()
                }
                self.networkManager.flush()
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
        self.deviceModel = DeviceInfo.machineModel()
        #else
        self.screenWidth = 0
        self.screenHeight = 0
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = "Mac"
        #endif

        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        self.locale = Locale.current.identifier
    }

    /// Returns the marketing device name (e.g. "iPhone 15 Pro") via sysctlbyname hw.machine lookup.
    /// Falls back to the raw identifier if unknown, or UIDevice.current.model if the syscall fails.
    private static func machineModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else {
            #if canImport(UIKit)
            return UIDevice.current.model
            #else
            return "Unknown"
            #endif
        }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        return DeviceModelMap.name(for: identifier)
    }
}

// MARK: - Device Model Map

private enum DeviceModelMap {
    static func name(for identifier: String) -> String {
        // Simulator: return the simulated device from environment
        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
                .flatMap { name(for: $0) } ?? identifier
        }
        return models[identifier] ?? identifier
    }

    // swiftlint:disable:next function_body_length
    private static let models: [String: String] = [
        // MARK: iPhone
        "iPhone8,1": "iPhone 6s",
        "iPhone8,2": "iPhone 6s Plus",
        "iPhone8,4": "iPhone SE",
        "iPhone9,1": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus",
        "iPhone9,3": "iPhone 7",
        "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X",
        "iPhone10,4": "iPhone 8",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE 2",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE 3",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",

        // MARK: iPad
        "iPad5,1": "iPad mini 4",
        "iPad5,2": "iPad mini 4",
        "iPad5,3": "iPad Air 2",
        "iPad5,4": "iPad Air 2",
        "iPad6,3": "iPad Pro 9.7\"",
        "iPad6,4": "iPad Pro 9.7\"",
        "iPad6,7": "iPad Pro 12.9\"",
        "iPad6,8": "iPad Pro 12.9\"",
        "iPad6,11": "iPad 5",
        "iPad6,12": "iPad 5",
        "iPad7,1": "iPad Pro 12.9\" 2",
        "iPad7,2": "iPad Pro 12.9\" 2",
        "iPad7,3": "iPad Pro 10.5\"",
        "iPad7,4": "iPad Pro 10.5\"",
        "iPad7,5": "iPad 6",
        "iPad7,6": "iPad 6",
        "iPad7,11": "iPad 7",
        "iPad7,12": "iPad 7",
        "iPad8,1": "iPad Pro 11\"",
        "iPad8,2": "iPad Pro 11\"",
        "iPad8,3": "iPad Pro 11\"",
        "iPad8,4": "iPad Pro 11\"",
        "iPad8,5": "iPad Pro 12.9\" 3",
        "iPad8,6": "iPad Pro 12.9\" 3",
        "iPad8,7": "iPad Pro 12.9\" 3",
        "iPad8,8": "iPad Pro 12.9\" 3",
        "iPad8,9": "iPad Pro 11\" 2",
        "iPad8,10": "iPad Pro 11\" 2",
        "iPad8,11": "iPad Pro 12.9\" 4",
        "iPad8,12": "iPad Pro 12.9\" 4",
        "iPad11,1": "iPad mini 5",
        "iPad11,2": "iPad mini 5",
        "iPad11,3": "iPad Air 3",
        "iPad11,4": "iPad Air 3",
        "iPad11,6": "iPad 8",
        "iPad11,7": "iPad 8",
        "iPad12,1": "iPad 9",
        "iPad12,2": "iPad 9",
        "iPad13,1": "iPad Air 4",
        "iPad13,2": "iPad Air 4",
        "iPad13,4": "iPad Pro 11\" 3",
        "iPad13,5": "iPad Pro 11\" 3",
        "iPad13,6": "iPad Pro 11\" 3",
        "iPad13,7": "iPad Pro 11\" 3",
        "iPad13,8": "iPad Pro 12.9\" 5",
        "iPad13,9": "iPad Pro 12.9\" 5",
        "iPad13,10": "iPad Pro 12.9\" 5",
        "iPad13,11": "iPad Pro 12.9\" 5",
        "iPad13,16": "iPad Air 5",
        "iPad13,17": "iPad Air 5",
        "iPad13,18": "iPad 10",
        "iPad13,19": "iPad 10",
        "iPad14,1": "iPad mini 6",
        "iPad14,2": "iPad mini 6",
        "iPad14,3": "iPad Pro 11\" 4",
        "iPad14,4": "iPad Pro 11\" 4",
        "iPad14,5": "iPad Pro 12.9\" 6",
        "iPad14,6": "iPad Pro 12.9\" 6",
        "iPad14,8": "iPad Air 11\" M2",
        "iPad14,9": "iPad Air 11\" M2",
        "iPad14,10": "iPad Air 13\" M2",
        "iPad14,11": "iPad Air 13\" M2",
        "iPad15,3": "iPad Air 11\" M3",
        "iPad15,4": "iPad Air 11\" M3",
        "iPad15,5": "iPad Air 13\" M3",
        "iPad15,6": "iPad Air 13\" M3",
        "iPad15,7": "iPad mini 7",
        "iPad15,8": "iPad mini 7",
        "iPad16,1": "iPad Pro 11\" M4",
        "iPad16,2": "iPad Pro 11\" M4",
        "iPad16,3": "iPad Pro 13\" M4",
        "iPad16,4": "iPad Pro 13\" M4",
        "iPad16,5": "iPad 11",
        "iPad16,6": "iPad 11",

        // MARK: iPod touch
        "iPod9,1": "iPod touch 7",
    ]
}
