import Testing
@testable import EmbrCLIKit

@Suite("Smoke")
struct SmokeTests {
    @Test func builds() {
        #expect(true)
    }
}
