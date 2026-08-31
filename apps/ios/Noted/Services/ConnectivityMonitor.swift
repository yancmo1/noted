@preconcurrency import Network
import Combine

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isReachable = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shepswork.noted.connectivity")
    var onReachable: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changedToReachable = reachable && !self.isReachable
                self.isReachable = reachable
                if changedToReachable { self.onReachable?() }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
