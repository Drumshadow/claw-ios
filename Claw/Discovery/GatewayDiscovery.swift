import Foundation
import Network

// MARK: - Discovered gateway

struct DiscoveredGateway: Identifiable, Equatable {
    let id: UUID
    let name: String
    let host: String
    let port: Int

    var asConfig: GatewayConfig {
        GatewayConfig(id: id, name: name, host: host, port: port)
    }

    static func == (lhs: DiscoveredGateway, rhs: DiscoveredGateway) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - GatewayDiscovery

/// Browses for `_openclaw._tcp.` Bonjour services on the local network.
/// Uses `NetServiceBrowser` (NSNetServiceBrowser via Foundation) to discover gateways
/// and `NetService.resolve` to obtain host/port.
@Observable
final class GatewayDiscovery: NSObject {

    // MARK: - Observable state

    private(set) var discovered: [DiscoveredGateway] = []
    private(set) var isSearching: Bool = false

    // MARK: - Private

    private var browser: NetServiceBrowser?
    /// Tracks in-flight NetService resolution — must hold strong refs
    private var resolvingServices: [NetService] = []

    // MARK: - Public interface

    func startDiscovery() {
        guard !isSearching else { return }
        isSearching = true

        let nb = NetServiceBrowser()
        nb.delegate = self
        browser = nb
        nb.searchForServices(ofType: "_openclaw._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        isSearching = false
        // Cancel any pending resolutions
        for svc in resolvingServices {
            svc.stop()
        }
        resolvingServices.removeAll()
    }

    func clearDiscovered() {
        discovered.removeAll()
    }

    // MARK: - Private helpers

    private func addOrUpdate(gateway: DiscoveredGateway) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let idx = self.discovered.firstIndex(where: { $0.id == gateway.id }) {
                self.discovered[idx] = gateway
            } else {
                self.discovered.append(gateway)
            }
        }
    }

    private func remove(serviceID: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.discovered.removeAll { $0.id == serviceID }
        }
    }
}

// MARK: - NetServiceBrowserDelegate

extension GatewayDiscovery: NetServiceBrowserDelegate {

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async { self.isSearching = true }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async { self.isSearching = false }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        DispatchQueue.main.async { self.isSearching = false }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 10.0)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        // Match by name + domain as a proxy ID
        let proxyID = stableID(for: service)
        DispatchQueue.main.async { [weak self] in
            self?.discovered.removeAll { UUID(uuidString: $0.id.uuidString) != nil && $0.name == service.name }
        }
        resolvingServices.removeAll { $0 === service }
    }

    private func stableID(for service: NetService) -> UUID {
        // Derive a stable UUID from the service name+domain combo
        let key = "\(service.name).\(service.domain)"
        let bytes = key.utf8.prefix(16)
        // Simple hash-based UUID v5 from name string (just use UUID(uuidString:) fallback)
        var hash = [UInt8](repeating: 0, count: 16)
        for (i, byte) in bytes.enumerated() {
            hash[i % 16] ^= byte
        }
        // Set version 5
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
    }
}

// MARK: - NetServiceDelegate

extension GatewayDiscovery: NetServiceDelegate {

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostname = sender.hostName else {
            resolvingServices.removeAll { $0 === sender }
            return
        }

        let port = sender.port
        let name = sender.name
        let id = stableID(for: sender)

        let gateway = DiscoveredGateway(
            id: id,
            name: name,
            host: hostname,
            port: port > 0 ? port : 3000
        )
        addOrUpdate(gateway: gateway)
        resolvingServices.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 === sender }
    }
}
