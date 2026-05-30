import XCTest
@testable import HeyClaudeKit

final class CommandTests: XCTestCase {
    func test_codableRoundTrip_allKinds() throws {
        let cmds = [
            Command(id: "cli", label: "Claude Code",
                    triggers: ["code"], kind: .runCLI(commandTemplate: "claude {prompt}"),
                    target: .editor(.cursor), acceptsPrompt: true,
                    editorIntegration: .claudeCode),
            Command(id: "term", label: "Claude (terminal)",
                    triggers: ["terminal"], kind: .runCLI(commandTemplate: "claude {prompt}"),
                    target: .terminal(.iterm2), acceptsPrompt: true),
            Command(id: "sh", label: "Run tests",
                    triggers: ["run tests"], kind: .runShell(script: "npm test"),
                    target: nil, acceptsPrompt: false),
        ]
        let data = try JSONEncoder().encode(cmds)
        XCTAssertEqual(try JSONDecoder().decode([Command].self, from: data), cmds)
    }

    func test_seededDefaults_areClaudeCodeOnly() {
        let seeded = Command.seededDefaults
        // No more "open Claude desktop chat app" command — Claude-Code-only.
        XCTAssertFalse(seeded.contains { if case .openApp = $0.kind { return true } else { return false } })
        let code = seeded.first { $0.id == "claude-code" }
        XCTAssertNotNil(code)
        XCTAssertTrue(code?.triggers.contains("code") ?? false)
        XCTAssertEqual(code?.editorIntegration, .claudeCode)   // editor-ready
    }

    func test_decodingLegacyCommand_migratesTerminalKeyToTarget() throws {
        // Pre-LaunchTarget command stored the destination as a bare `terminal`.
        let legacy = #"{"id":"claude-code","label":"Claude Code","triggers":["code"],"kind":{"runCLI":{"commandTemplate":"claude {prompt}"}},"terminal":"Ghostty","acceptsPrompt":true}"#
        let c = try JSONDecoder().decode(Command.self, from: Data(legacy.utf8))
        XCTAssertEqual(c.target, .terminal(.ghostty))
    }
}
