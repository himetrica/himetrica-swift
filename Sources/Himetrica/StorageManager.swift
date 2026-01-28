import Foundation

/// Manages persistent storage for the Himetrica SDK
final class StorageManager {
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let queueDirectory: URL

    // UserDefaults keys
    private enum Keys {
        static let visitorId = "hm_visitor_id"
        static let sessionId = "hm_session_id"
        static let sessionTimestamp = "hm_session_timestamp"
        static let originalReferrer = "hm_original_referrer"
    }

    init() {
        self.userDefaults = UserDefaults.standard
        self.fileManager = FileManager.default

        // Create queue directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.queueDirectory = appSupport.appendingPathComponent("Himetrica/EventQueue", isDirectory: true)

        try? fileManager.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Visitor ID (persistent across app launches)

    func getVisitorId() -> String {
        if let existingId = userDefaults.string(forKey: Keys.visitorId) {
            return existingId
        }

        let newId = UUID().uuidString
        userDefaults.set(newId, forKey: Keys.visitorId)
        return newId
    }

    // MARK: - Session Management

    func getSessionId(timeout: TimeInterval) -> String {
        let now = Date()
        let lastTimestamp = userDefaults.object(forKey: Keys.sessionTimestamp) as? Date

        // Check if session has expired
        if let timestamp = lastTimestamp,
           let existingSessionId = userDefaults.string(forKey: Keys.sessionId),
           now.timeIntervalSince(timestamp) < timeout {
            // Session still valid, update timestamp
            userDefaults.set(now, forKey: Keys.sessionTimestamp)
            return existingSessionId
        }

        // Create new session
        let newSessionId = UUID().uuidString
        userDefaults.set(newSessionId, forKey: Keys.sessionId)
        userDefaults.set(now, forKey: Keys.sessionTimestamp)

        // Clear original referrer for new session
        userDefaults.removeObject(forKey: Keys.originalReferrer)

        return newSessionId
    }

    func updateSessionTimestamp() {
        userDefaults.set(Date(), forKey: Keys.sessionTimestamp)
    }

    // MARK: - Referrer (deep link attribution)

    func getOriginalReferrer() -> String {
        return userDefaults.string(forKey: Keys.originalReferrer) ?? ""
    }

    func setOriginalReferrer(_ referrer: String) {
        // Only set if not already set for this session
        if userDefaults.string(forKey: Keys.originalReferrer) == nil {
            userDefaults.set(referrer, forKey: Keys.originalReferrer)
        }
    }

    // MARK: - Event Queue (offline support)

    func enqueueEvent(_ event: QueuedEvent) {
        let filePath = queueDirectory.appendingPathComponent("\(event.id).json")
        if let data = try? JSONEncoder().encode(event) {
            try? data.write(to: filePath)
        }
    }

    func dequeueEvents(limit: Int) -> [QueuedEvent] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        // Sort by creation date (oldest first)
        let sortedFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 < date2
            }
            .prefix(limit)

        return sortedFiles.compactMap { url -> QueuedEvent? in
            guard let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(QueuedEvent.self, from: data) else {
                return nil
            }
            return event
        }
    }

    func removeEvent(id: String) {
        let filePath = queueDirectory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: filePath)
    }

    func updateEvent(_ event: QueuedEvent) {
        let filePath = queueDirectory.appendingPathComponent("\(event.id).json")
        if let data = try? JSONEncoder().encode(event) {
            try? data.write(to: filePath)
        }
    }

    func queueCount() -> Int {
        let files = try? fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return files?.filter { $0.pathExtension == "json" }.count ?? 0
    }

    func pruneQueue(maxSize: Int) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard jsonFiles.count > maxSize else { return }

        // Sort by creation date (oldest first) and remove excess
        let sortedFiles = jsonFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 < date2
        }

        let filesToRemove = sortedFiles.prefix(jsonFiles.count - maxSize)
        for file in filesToRemove {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - Reset

    func reset() {
        // Clear visitor data
        userDefaults.removeObject(forKey: Keys.visitorId)
        userDefaults.removeObject(forKey: Keys.sessionId)
        userDefaults.removeObject(forKey: Keys.sessionTimestamp)
        userDefaults.removeObject(forKey: Keys.originalReferrer)

        // Clear event queue
        if let files = try? fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
