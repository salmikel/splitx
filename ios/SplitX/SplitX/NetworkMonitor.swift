import Network
import SwiftUI

// Wraps NWPathMonitor and publishes isOnline on the main queue.
// DispatchQueue.main.async is used instead of Task {@MainActor} because
// NWPathMonitor's pathUpdateHandler fires on a background queue and the
// Task-based hop is unreliable for triggering @Published changes promptly.

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.splitx.NetworkMonitor", qos: .background)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
