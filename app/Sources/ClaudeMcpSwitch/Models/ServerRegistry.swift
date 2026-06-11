import Foundation

struct ServerRegistry: Codable, Equatable {
    var version: Int
    var servers: [ManagedServer]

    init(version: Int = 1, servers: [ManagedServer] = []) {
        self.version = version
        self.servers = servers
    }
}
