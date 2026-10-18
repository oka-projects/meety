import Foundation
@testable import MeetyCore
import Testing

/// Usa os CLIs reais do Claude e do Codex (conta da pessoa). Só com MEETY_NETWORK=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1"))
struct CLITests {
    @Test(arguments: CLISummarizer.Tool.allCases)
    func answersOK(tool: CLISummarizer.Tool) async throws {
        let found = CLISummarizer.candidates(tool)
        print("\(tool): \(found.map { "\($0.origin) \($0.url.path)" })")
        try #require(!found.isEmpty)
        let s = CLISummarizer(tool: tool)
        let out = try await s.run(system: "Answer with one word.", user: "Reply with the single word OK.", timeout: 120, onPartial: { _ in })
        #expect(out.uppercased().contains("OK"))
    }
}
