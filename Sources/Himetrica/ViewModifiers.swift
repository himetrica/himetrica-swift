import SwiftUI

// MARK: - Screen Tracking Modifier

/// A view modifier that tracks screen views automatically
public struct HimetricaScreenModifier: ViewModifier {
    let screenName: String
    let properties: [String: Any]?

    @Environment(\.scenePhase) private var scenePhase

    public init(screenName: String, properties: [String: Any]? = nil) {
        self.screenName = screenName
        self.properties = properties
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    Himetrica.shared.trackScreen(name: screenName, properties: properties)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                Task { @MainActor in
                    Himetrica.shared.handleScenePhase(newPhase)
                }
            }
    }
}

// MARK: - View Extensions

public extension View {
    /// Tracks this view as a screen when it appears
    /// - Parameters:
    ///   - name: The name of the screen to track
    ///   - properties: Optional additional properties to include with the screen view
    /// - Returns: A view that tracks screen views
    func trackScreen(_ name: String, properties: [String: Any]? = nil) -> some View {
        modifier(HimetricaScreenModifier(screenName: name, properties: properties))
    }

    /// Tracks a custom event when this view is tapped
    /// - Parameters:
    ///   - eventName: The name of the event to track
    ///   - properties: Optional properties to include with the event
    /// - Returns: A view that tracks the event on tap
    func trackOnTap(_ eventName: String, properties: [String: Any]? = nil) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                Task { @MainActor in
                    Himetrica.shared.track(eventName, properties: properties)
                }
            }
        )
    }
}

// MARK: - Error Tracking Modifier

public extension View {
    /// Tracks an error when it occurs
    /// - Parameters:
    ///   - error: The error to track
    ///   - context: Optional additional context
    /// - Returns: A view that tracks the error
    func trackError(_ error: Error, context: [String: Any]? = nil) -> some View {
        self.onAppear {
            Task { @MainActor in
                Himetrica.shared.captureError(error, context: context)
            }
        }
    }
}

// MARK: - App Lifecycle Modifier

/// A view modifier that handles app lifecycle events for analytics
public struct HimetricaLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    public func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { newPhase in
                Task { @MainActor in
                    Himetrica.shared.handleScenePhase(newPhase)
                }
            }
    }
}

public extension View {
    /// Adds Himetrica lifecycle handling to this view (typically used on the root view)
    /// - Returns: A view that handles app lifecycle events for analytics
    func himetricaLifecycle() -> some View {
        modifier(HimetricaLifecycleModifier())
    }
}

// MARK: - Deep Link Handling

public extension View {
    /// Handles deep links for Himetrica attribution tracking
    /// - Parameter action: Optional additional action to perform with the URL
    /// - Returns: A view that handles deep links
    func himetricaDeepLink(perform action: ((URL) -> Void)? = nil) -> some View {
        onOpenURL { url in
            Task { @MainActor in
                Himetrica.shared.setReferrer(from: url)
            }
            action?(url)
        }
    }
}

// MARK: - Button with Tracking

/// A button that automatically tracks tap events
public struct TrackedButton<Label: View>: View {
    let eventName: String
    let properties: [String: Any]?
    let action: () -> Void
    let label: () -> Label

    public init(
        _ eventName: String,
        properties: [String: Any]? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.eventName = eventName
        self.properties = properties
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button {
            Task { @MainActor in
                Himetrica.shared.track(eventName, properties: properties)
            }
            action()
        } label: {
            label()
        }
    }
}

// Convenience initializer for text buttons
public extension TrackedButton where Label == Text {
    init(
        _ eventName: String,
        title: String,
        properties: [String: Any]? = nil,
        action: @escaping () -> Void
    ) {
        self.eventName = eventName
        self.properties = properties
        self.action = action
        self.label = { Text(title) }
    }
}
