# Himetrica iOS SDK

A lightweight, privacy-focused analytics SDK for iOS, macOS, tvOS, and watchOS apps built with SwiftUI.

## Features

- **Screen tracking** - Automatic view tracking with SwiftUI modifiers
- **Custom events** - Track user actions with custom properties
- **User identification** - Associate analytics with user profiles
- **Session management** - Automatic session handling with configurable timeout
- **Offline support** - Events queued and sent when connectivity is restored
- **Duration tracking** - Automatic time-on-screen measurement
- **Deep link attribution** - Track where users came from
- **Privacy compliant** - Respects App Tracking Transparency (ATT)

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add the package dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/himetrica-swift", from: "1.0.0")
]
```

Or add it in Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL
3. Select the version and add to your target

## Quick Start

### 1. Initialize the SDK

Configure Himetrica in your app's entry point:

```swift
import SwiftUI
import Himetrica

@main
struct MyApp: App {
    init() {
        Himetrica.configure(apiKey: "your-api-key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .himetricaLifecycle()  // Handle app lifecycle events
                .himetricaDeepLink()   // Track deep link attribution
        }
    }
}
```

### 2. Track Screen Views

Add the `.trackScreen()` modifier to your views:

```swift
struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                // Your content
            }
        }
        .trackScreen("Home")
    }
}

struct ProductDetailView: View {
    let product: Product

    var body: some View {
        ScrollView {
            // Your content
        }
        .trackScreen("Product Detail", properties: [
            "product_id": product.id,
            "category": product.category
        ])
    }
}
```

### 3. Track Custom Events

```swift
struct CheckoutView: View {
    var body: some View {
        VStack {
            Button("Complete Purchase") {
                completePurchase()

                // Track the event
                Himetrica.shared.track("purchase_completed", properties: [
                    "product_id": "pro_plan",
                    "price": 9.99,
                    "currency": "USD"
                ])
            }
        }
        .trackScreen("Checkout")
    }
}

// Or use TrackedButton for automatic tracking
TrackedButton("signup_clicked", title: "Sign Up") {
    performSignup()
}

// Or use the trackOnTap modifier
Text("Learn More")
    .trackOnTap("learn_more_tapped")
```

### 4. Identify Users

Associate analytics data with a user after login:

```swift
func onUserLogin(user: User) {
    Himetrica.shared.identify(
        name: user.name,
        email: user.email,
        metadata: [
            "plan": user.subscriptionPlan,
            "signup_date": user.createdAt.ISO8601Format(),
            "is_verified": user.isEmailVerified
        ]
    )
}
```

## Configuration

### Full Configuration Options

```swift
let config = HimetricaConfig(
    apiKey: "your-api-key",
    apiUrl: "https://app.himetrica.com",  // Custom API URL (self-hosted)
    sessionTimeout: 30 * 60,               // Session timeout (default: 30 min)
    autoTrackScreenViews: true,            // Auto-track NavigationStack
    respectAdTracking: true,               // Respect ATT settings
    enableLogging: false,                  // Debug logging
    maxQueueSize: 1000,                    // Max offline queue size
    flushInterval: 30                      // Queue flush interval (seconds)
)

Himetrica.configure(with: config)
```

### Debug Mode

Enable logging during development:

```swift
#if DEBUG
let config = HimetricaConfig(
    apiKey: "your-api-key",
    enableLogging: true
)
#else
let config = HimetricaConfig(apiKey: "your-api-key")
#endif

Himetrica.configure(with: config)
```

## SwiftUI View Modifiers

### Screen Tracking

```swift
// Basic screen tracking
.trackScreen("Screen Name")

// With properties
.trackScreen("Screen Name", properties: ["key": "value"])
```

### Event Tracking on Tap

```swift
// Track when a view is tapped
Text("Learn More")
    .trackOnTap("learn_more_tapped")

// With properties
Image(systemName: "heart")
    .trackOnTap("favorite_tapped", properties: ["item_id": item.id])
```

### Lifecycle Handling

```swift
// Add to your root view to handle app lifecycle
ContentView()
    .himetricaLifecycle()
```

### Deep Link Attribution

```swift
// Track deep links and optionally handle them
ContentView()
    .himetricaDeepLink { url in
        // Handle the URL in your app
        router.navigate(to: url)
    }
```

## TrackedButton

A convenience component that tracks events automatically:

```swift
// With custom label
TrackedButton("signup_button_clicked") {
    performSignup()
} label: {
    HStack {
        Image(systemName: "person.badge.plus")
        Text("Sign Up")
    }
}

// Simple text button
TrackedButton("login_clicked", title: "Log In") {
    performLogin()
}

// With properties
TrackedButton("add_to_cart", properties: ["product_id": product.id]) {
    addToCart(product)
} label: {
    Text("Add to Cart")
}
```

## Features

### Automatic Session Management

Sessions automatically expire after 30 minutes of inactivity (configurable). A new session is created when:
- The app is launched for the first time
- The session timeout has elapsed since the last activity

### Offline Support

Events are automatically queued when offline:
- Events are persisted to disk and survive app restarts
- Queue is automatically flushed when connectivity returns
- Failed events are retried up to 3 times
- Queue is pruned to prevent unbounded growth

### Screen Duration Tracking

The SDK automatically tracks how long users spend on each screen. Duration is sent when:
- The user navigates to a new screen
- The app goes to the background
- The app is terminated

### Deep Link Attribution

Handle deep links to track where users came from:

```swift
ContentView()
    .himetricaDeepLink { url in
        // Handle the URL in your app
        router.navigate(to: url)
    }
```

## API Reference

### Himetrica

| Method | Description |
|--------|-------------|
| `configure(apiKey:)` | Initialize with API key |
| `configure(with:)` | Initialize with full configuration |
| `trackScreen(name:properties:)` | Track a screen view |
| `track(_:properties:)` | Track a custom event |
| `identify(name:email:metadata:)` | Identify the current user |
| `setReferrer(from:)` | Set attribution from a URL |
| `handleScenePhase(_:)` | Handle app lifecycle changes |
| `flush()` | Force flush the event queue |
| `reset()` | Clear all stored data |
| `visitorId` | Get the current visitor ID |

### HimetricaConfig

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `apiKey` | `String` | required | Your Himetrica API key |
| `apiUrl` | `String` | `https://app.himetrica.com` | API endpoint URL |
| `sessionTimeout` | `TimeInterval` | `1800` (30 min) | Session expiry time |
| `autoTrackScreenViews` | `Bool` | `true` | Auto-track navigation |
| `respectAdTracking` | `Bool` | `true` | Respect ATT settings |
| `enableLogging` | `Bool` | `false` | Enable debug logging |
| `maxQueueSize` | `Int` | `1000` | Max queued events |
| `flushInterval` | `TimeInterval` | `30` | Queue flush interval |

### View Modifiers

| Modifier | Description |
|----------|-------------|
| `.trackScreen(_:properties:)` | Track when view appears |
| `.trackOnTap(_:properties:)` | Track on tap gesture |
| `.himetricaLifecycle()` | Handle app lifecycle |
| `.himetricaDeepLink(perform:)` | Handle deep links |

## Data Collected

The SDK automatically collects:

| Data | Description |
|------|-------------|
| Visitor ID | Persistent UUID (stored in UserDefaults) |
| Session ID | UUID that expires after inactivity |
| Screen name | The name you provide |
| Screen size | Device screen dimensions |
| App version | From Info.plist |
| OS version | iOS/macOS version |
| Device model | iPhone, iPad, Mac, etc. |
| Locale | User's language/region |
| Duration | Time spent on each screen |

## Privacy

### App Tracking Transparency

The SDK respects ATT by default. When `respectAdTracking` is `true`:
- Tracking works normally if ATT status is `.authorized` or `.notDetermined`
- Tracking is disabled if user denies permission

To track regardless of ATT (ensure compliance with Apple guidelines):

```swift
HimetricaConfig(apiKey: "key", respectAdTracking: false)
```

### Data Residency

For GDPR compliance or data residency requirements, use a custom API URL:

```swift
HimetricaConfig(
    apiKey: "key",
    apiUrl: "https://eu.your-instance.com"
)
```

## Troubleshooting

### Events not being sent

1. Enable logging: `enableLogging: true`
2. Check the console for `[Himetrica]` messages
3. Verify your API key is correct
4. Check network connectivity

### Session not persisting

Sessions are stored in memory and UserDefaults. If sessions reset unexpectedly:
1. Ensure `sessionTimeout` is set appropriately
2. Check that UserDefaults isn't being cleared

### High battery usage

Reduce flush frequency for battery-sensitive apps:

```swift
HimetricaConfig(apiKey: "key", flushInterval: 60)
```

## License

MIT License
