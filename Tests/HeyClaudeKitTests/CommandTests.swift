import XCTest
@testable import HeyClaudeKit

final class CommandTests: XCTestCase {
    func test_codableRoundTrip_allKinds() throws {
        let cmds = [
            Command(id: "cli", label: "Claude Code",
                    triggers: ["code"], kind: .runCLI(commandTemplate: "claude {prompt}"),
                    terminal: .iterm2, acceptsPrompt: true),
            Command(id: "app", label: "Claude desktop",
                    triggers: [], kind: .openApp(bundleID: "com.anthropic.claudefordesktop"),
                    terminal: nil, acceptsPrompt: false),
            Command(id: "sh", label: "Run tests",
                    triggers: ["run tests"], kind: .runShell(script: "npm test"),
                    terminal: nil, acceptsPrompt: false),
        ]
        let data = try JSONEncoder().encode(cmds)
        XCTAssertEqual(try JSONDecoder().decode([Command].self, from: data), cmds)
    }

    func test_seededDefaults_containChatAndCode() {
        let seeded = Command.seededDefaults
        XCTAssertTrue(seeded.contains { if case .openApp = $0.kind { return $0.triggers.isEmpty } else { return false } })
        XCTAssertTrue(seeded.contains { $0.triggers.contains("code") })
    }
}
