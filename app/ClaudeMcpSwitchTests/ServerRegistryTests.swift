import Foundation
import Testing
@testable import ClaudeMcpSwitch

struct ServerRegistryTests {
    @Test func codableRoundTripPreservesServers() throws {
        let registry = ServerRegistry(
            version: 1,
            servers: [
                ManagedServer(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    name: "github",
                    enabled: true,
                    config: MCPServerConfig(
                        command: "npx",
                        args: ["-y", "@modelcontextprotocol/server-github"],
                        env: ["TOKEN": "secret"]
                    ),
                    notes: "seed",
                    createdAt: .distantPast,
                    updatedAt: .distantFuture
                )
            ]
        )

        let data = try JSONEncoder().encode(registry)
        let decoded = try JSONDecoder().decode(ServerRegistry.self, from: data)

        #expect(decoded == registry)
    }
}
