import Testing
@testable import EmbrCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Package version is present")
    func version() {
        #expect(EmbrCore.version == "0.1.0")
    }
}
