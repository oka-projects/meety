import Foundation
@testable import MeetyCore
import Testing

/// Testes que usam a rede. Só rodam com MEETY_NETWORK=1 (e MEETY_REPO para escolher o repositório):
///   MEETY_NETWORK=1 MEETY_REPO=FluidInference/speaker-diarization-coreml MEETY_DEST=~/Library/... swift test --filter NetworkTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1"))
struct NetworkTests {
    @Test func downloadsRepository() async throws {
        let env = ProcessInfo.processInfo.environment
        let repo = env["MEETY_REPO"] ?? "FluidInference/speaker-diarization-coreml"
        let dest = env["MEETY_DEST"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("meety-dl-test/\(repo)")
        var last: HuggingFaceDownloader.Progress?
        let lock = NSLock()
        try await HuggingFaceDownloader.download(repo: repo, into: dest) { p in lock.lock(); last = p; lock.unlock() }
        try "ok".write(to: dest.appendingPathComponent(".meety-complete"), atomically: true, encoding: .utf8)
        lock.lock(); let final = last; lock.unlock()
        #expect(final?.fraction == 1)
        let files = try await HuggingFaceDownloader.listFiles(repo: repo)
        for f in files where !f.path.hasPrefix(".git") {
            let size = try dest.appendingPathComponent(f.path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
            #expect(Int64(size) == f.size, "\(f.path)")
        }
    }
}
