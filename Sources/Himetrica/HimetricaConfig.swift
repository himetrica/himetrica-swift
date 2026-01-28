import Foundation

/// Configuration options for the Himetrica SDK
public struct HimetricaConfig {
    /// The API key for your Himetrica project
    public let apiKey: String

    /// The base URL for the Himetrica API (defaults to https://app.himetrica.com)
    public let apiUrl: String

    /// Session timeout in seconds (defaults to 30 minutes)
    public let sessionTimeout: TimeInterval

    /// Whether to automatically track screen views (defaults to true)
    public let autoTrackScreenViews: Bool

    /// Whether to respect the user's limit ad tracking setting (defaults to true)
    public let respectAdTracking: Bool

    /// Whether to enable debug logging (defaults to false)
    public let enableLogging: Bool

    /// Maximum number of events to queue when offline (defaults to 1000)
    public let maxQueueSize: Int

    /// Interval for flushing the event queue in seconds (defaults to 30)
    public let flushInterval: TimeInterval

    /// Creates a new Himetrica configuration
    /// - Parameters:
    ///   - apiKey: The API key for your Himetrica project
    ///   - apiUrl: The base URL for the Himetrica API
    ///   - sessionTimeout: Session timeout in seconds
    ///   - autoTrackScreenViews: Whether to automatically track screen views
    ///   - respectAdTracking: Whether to respect the user's limit ad tracking setting
    ///   - enableLogging: Whether to enable debug logging
    ///   - maxQueueSize: Maximum number of events to queue when offline
    ///   - flushInterval: Interval for flushing the event queue in seconds
    public init(
        apiKey: String,
        apiUrl: String = "https://app.himetrica.com",
        sessionTimeout: TimeInterval = 30 * 60,
        autoTrackScreenViews: Bool = true,
        respectAdTracking: Bool = true,
        enableLogging: Bool = false,
        maxQueueSize: Int = 1000,
        flushInterval: TimeInterval = 30
    ) {
        self.apiKey = apiKey
        self.apiUrl = apiUrl
        self.sessionTimeout = sessionTimeout
        self.autoTrackScreenViews = autoTrackScreenViews
        self.respectAdTracking = respectAdTracking
        self.enableLogging = enableLogging
        self.maxQueueSize = maxQueueSize
        self.flushInterval = flushInterval
    }
}
