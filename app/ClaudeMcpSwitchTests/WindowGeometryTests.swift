import CoreGraphics
import Testing
@testable import ClaudeMcpSwitch

struct WindowGeometryTests {
    @Test func activationPolicyReflectsWindowPresence() {
        #expect(activationPolicy(hasOpenWindows: true) == .regular)
        #expect(activationPolicy(hasOpenWindows: false) == .accessory)
    }

    @Test func windowCenteredOriginPreservesRequestedTopEdge() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let visibleFrame = CGRect(x: 100, y: 100, width: 1000, height: 800)

        let origin = windowCenteredOrigin(
            frame: frame,
            visibleFrame: visibleFrame,
            topEdge: 900
        )

        #expect(origin.x == 400)
        #expect(origin.y == 600)
    }
}
