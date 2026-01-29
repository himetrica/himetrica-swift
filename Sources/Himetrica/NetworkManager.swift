import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages network requests for the Himetrica SDK
final class NetworkManager {
    private let config: HimetricaConfig
    private let session: URLSession
    private let storageManager: StorageManager
    private var flushTimer: Timer?
    private let queue = DispatchQueue(label: "com.himetrica.network", qos: .utility)
    private var isOnline = true

    init(config: HimetricaConfig, storageManager: StorageManager) {
        self.config = config
        self.storageManager = storageManager

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        sessionConfig.waitsForConnectivity = true
        self.session = URLSession(configuration: sessionConfig)

        setupReachabilityMonitoring()
        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
    }

    // MARK: - Public Methods

    func sendEvent<T: Encodable>(endpoint: String, data: T, completion: ((Bool) -> Void)? = nil) {
        guard let jsonData = try? JSONEncoder().encode(data) else {
            log("Failed to encode event data")
            completion?(false)
            return
        }

        if isOnline {
            performRequest(endpoint: endpoint, data: jsonData) { [weak self] success in
                if !success {
                    self?.queueEvent(endpoint: endpoint, data: jsonData)
                }
                completion?(success)
            }
        } else {
            queueEvent(endpoint: endpoint, data: jsonData)
            completion?(false)
        }
    }

    func sendBeacon(endpoint: String, data: Data) {
        // Beacons are fire-and-forget, but we still queue if offline
        if isOnline {
            performRequest(endpoint: endpoint, data: data, isBeacon: true) { [weak self] success in
                if !success {
                    self?.queueEvent(endpoint: endpoint, data: data)
                }
            }
        } else {
            queueEvent(endpoint: endpoint, data: data)
        }
    }

    func flush() {
        queue.async { [weak self] in
            self?.processQueue()
        }
    }

    // MARK: - Private Methods

    private func performRequest(
        endpoint: String,
        data: Data,
        isBeacon: Bool = false,
        completion: @escaping (Bool) -> Void
    ) {
        let urlString: String
        if isBeacon && endpoint.contains("beacon") {
            urlString = "\(config.apiUrl)\(endpoint)&apiKey=\(config.apiKey)"
        } else if endpoint.contains("?") {
            urlString = "\(config.apiUrl)\(endpoint)"
        } else {
            urlString = "\(config.apiUrl)\(endpoint)"
        }

        guard let url = URL(string: urlString) else {
            log("Invalid URL: \(urlString)")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = data

        let task = session.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.log("Request failed: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false)
                return
            }

            let success = (200...299).contains(httpResponse.statusCode)
            if !success {
                self?.log("Request failed with status: \(httpResponse.statusCode)")
            }
            completion(success)
        }

        task.resume()
    }

    private func queueEvent(endpoint: String, data: Data) {
        let event = QueuedEvent(endpoint: endpoint, data: data)
        storageManager.enqueueEvent(event)
        storageManager.pruneQueue(maxSize: config.maxQueueSize)
        log("Event queued for later delivery")
    }

    private func processQueue() {
        guard isOnline else { return }

        let events = storageManager.dequeueEvents(limit: 50)
        guard !events.isEmpty else { return }

        log("Processing \(events.count) queued events")

        let group = DispatchGroup()

        for event in events {
            group.enter()
            performRequest(endpoint: event.endpoint, data: event.data) { [weak self] success in
                if success {
                    self?.storageManager.removeEvent(id: event.id)
                } else if event.retryCount < 3 {
                    self?.storageManager.updateEvent(event.incrementingRetry())
                } else {
                    // Max retries reached, discard the event
                    self?.storageManager.removeEvent(id: event.id)
                    self?.log("Event discarded after max retries")
                }
                group.leave()
            }
        }

        group.wait()
    }

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: self.config.flushInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func setupReachabilityMonitoring() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isOnline = true
            self?.flush()
        }
        #endif
    }

    private func log(_ message: String) {
        guard config.enableLogging else { return }
        print("[Himetrica] \(message)")
    }
}
