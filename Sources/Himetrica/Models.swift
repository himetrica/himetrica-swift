import Foundation

/// Severity level for error events
public enum ErrorSeverity: String, Codable {
    case error, warning, info
}

/// Represents an error event
struct ErrorEvent: Codable {
    let visitorId: String
    let sessionId: String
    let type: String           // "error", "unhandledrejection", "console"
    let message: String
    let stack: String?
    let source: String?
    let lineno: Int?
    let colno: Int?
    let severity: String       // "error", "warning", "info"
    let path: String
    let userAgent: String
    let timestamp: Int
    let context: [String: AnyCodable]?
}

/// Represents a screen view event
struct ScreenViewEvent: Codable {
    let visitorId: String
    let sessionId: String
    let pageViewId: String
    let path: String
    let title: String
    let referrer: String
    let queryString: String
    let screenWidth: Int
    let screenHeight: Int
    let platform: String
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let locale: String
}

/// Represents a duration beacon event
struct DurationEvent: Codable {
    let pageViewId: String
    let duration: Int
}

/// Represents a custom event
struct CustomEvent: Codable {
    let visitorId: String
    let sessionId: String
    let eventName: String
    let properties: [String: AnyCodable]?
    let path: String
    let title: String
    let queryString: String
    let platform: String
}

/// Represents a heartbeat event (lightweight lastSeenAt refresh)
struct HeartbeatEvent: Codable {
    let visitorId: String
    let sessionId: String
}

/// Represents an identify event
struct IdentifyEvent: Codable {
    let visitorId: String
    let name: String?
    let email: String?
    let metadata: [String: AnyCodable]?
}

/// A type-erased Codable value for handling dynamic properties
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unable to encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

/// Wrapper for queued events that includes metadata for persistence
struct QueuedEvent: Codable {
    let id: String
    let endpoint: String
    let data: Data
    let timestamp: Date
    let retryCount: Int

    init(endpoint: String, data: Data) {
        self.id = UUID().uuidString
        self.endpoint = endpoint
        self.data = data
        self.timestamp = Date()
        self.retryCount = 0
    }

    func incrementingRetry() -> QueuedEvent {
        QueuedEvent(
            id: id,
            endpoint: endpoint,
            data: data,
            timestamp: timestamp,
            retryCount: retryCount + 1
        )
    }

    private init(id: String, endpoint: String, data: Data, timestamp: Date, retryCount: Int) {
        self.id = id
        self.endpoint = endpoint
        self.data = data
        self.timestamp = timestamp
        self.retryCount = retryCount
    }
}
