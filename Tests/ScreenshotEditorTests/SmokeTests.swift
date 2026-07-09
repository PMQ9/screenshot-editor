import Testing

@Suite struct SmokeTests {
    @Test func toolchainRunsTests() {
        #expect(1 + 1 == 2)
    }
}
