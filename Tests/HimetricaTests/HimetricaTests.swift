import XCTest
@testable import Himetrica

final class HimetricaTests: XCTestCase {
    func testAnyCodableEncodesString() throws {
        let value = AnyCodable("test")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? String, "test")
    }

    func testAnyCodableEncodesInt() throws {
        let value = AnyCodable(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func testAnyCodableEncodesBool() throws {
        let value = AnyCodable(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Bool, true)
    }

    func testAnyCodableEncodesDouble() throws {
        let value = AnyCodable(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Double, 3.14)
    }

    func testAnyCodableEncodesDictionary() throws {
        let dict: [String: Any] = ["key": "value", "number": 123]
        let value = AnyCodable(dict)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        guard let decodedDict = decoded.value as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }
        XCTAssertEqual(decodedDict["key"] as? String, "value")
        XCTAssertEqual(decodedDict["number"] as? Int, 123)
    }

    func testQueuedEventCreation() {
        let data = "test".data(using: .utf8)!
        let event = QueuedEvent(endpoint: "/test", data: data)

        XCTAssertFalse(event.id.isEmpty)
        XCTAssertEqual(event.endpoint, "/test")
        XCTAssertEqual(event.retryCount, 0)
    }

    func testQueuedEventIncrementRetry() {
        let data = "test".data(using: .utf8)!
        let event = QueuedEvent(endpoint: "/test", data: data)
        let retriedEvent = event.incrementingRetry()

        XCTAssertEqual(retriedEvent.id, event.id)
        XCTAssertEqual(retriedEvent.retryCount, 1)
    }
}
