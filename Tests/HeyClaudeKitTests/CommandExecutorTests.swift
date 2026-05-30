import XCTest
@testable import HeyClaudeKit

final class CommandExecutorTests: XCTestCase {
    final class MockLauncher: TerminalLauncher, @unchecked Sendable {
        var launched: [LaunchSpec] = []
        func isAvailable() -> Bool { true }
        func launch(_ spec: LaunchSpec) throws { launched.append(spec) }
    }

    /// A launcher that always fails — for the failure-path tests.
    final class FailingLauncher: TerminalLauncher, @unchecked Sendable {
        let error: TerminalLaunchError
        init(_ error: TerminalLaunchError) { self.error = error }
        func isAvailable() -> Bool { false }
        func launch(_ spec: LaunchSpec) throws { throw error }
    }

    /// Adapts the old simple test doubles to the new seams: `openApp` reports
    /// success after recording the bundle, `runShell` is non-throwing.
    private func exec(_ mock: TerminalLauncher,
                      openedApps: @escaping @Sendable (String) -> Void = { _ in },
                      ranShell: @escaping @Sendable (String) -> Void = { _ in }) -> CommandExecutor {
        CommandExecutor(settings: .default, launcherFor: { _ in mock },
                        openApp: { bundle, done in openedApps(bundle); done(.success(())) },
                        runShell: { ranShell($0) })
    }

    /// Runs `execute` and returns the (synchronously delivered) result.
    private func run(_ executor: CommandExecutor, _ command: Command,
                     prompt: String?) -> Result<Void, LaunchFailure> {
        let box = Box<Result<Void, LaunchFailure>?>(nil)
        executor.execute(command, prompt: prompt) { box.value = $0 }
        return box.value ?? .failure(.appNotFound("no result delivered"))
    }

    /// `Result<Void, _>` can't be `Equatable` (Void isn't), so compare the unwrapped
    /// `LaunchFailure` (which is).
    private func assertFailure(_ result: Result<Void, LaunchFailure>, _ expected: LaunchFailure,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let f) = result else {
            return XCTFail("expected failure \(expected), got success", file: file, line: line)
        }
        XCTAssertEqual(f, expected, file: file, line: line)
    }

    // MARK: - Success paths (kept meaningful)

    func test_runCLI_substitutesPrompt() {
        let mock = MockLauncher()
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        XCTAssertNoThrow(try run(exec(mock), cmd, prompt: "fix the bug").get())
        XCTAssertEqual(mock.launched.first?.shellCommand().contains("claude 'fix the bug'"), true)
    }
    func test_runCLI_noPrompt_dropsPlaceholder() {
        let mock = MockLauncher()
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        _ = run(exec(mock), cmd, prompt: nil)
        let sh = mock.launched.first!.shellCommand()
        XCTAssertTrue(sh.contains("claude") && !sh.contains("{prompt}") && !sh.contains("''"))
    }
    func test_openApp_callsOpenWithBundleID() {
        let opened = Box<String?>(nil)
        let result = run(exec(MockLauncher(), openedApps: { opened.value = $0 }),
                         Command(id: "a", label: "App", triggers: [], kind: .openApp(bundleID: "com.x.y")),
                         prompt: nil)
        XCTAssertEqual(opened.value, "com.x.y")
        XCTAssertNoThrow(try result.get())
    }
    func test_runShell_callsRunWithScript() {
        let ran = Box<String?>(nil)
        let result = run(exec(MockLauncher(), ranShell: { ran.value = $0 }),
                         Command(id: "s", label: "Sh", triggers: ["t"], kind: .runShell(script: "npm test")),
                         prompt: nil)
        XCTAssertEqual(ran.value, "npm test")
        XCTAssertNoThrow(try result.get())
    }
    func test_runCLI_editorTarget_opensDeepLinkInsteadOfTerminal() {
        let mock = MockLauncher()
        let opened = Box<URL?>(nil)
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in mock },
                                       openURL: { opened.value = $0; return true })
        let cmd = Command(id: "claude-code", label: "Claude Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"),
                          target: .editor(.cursor), acceptsPrompt: true,
                          editorIntegration: .claudeCode)
        let result = run(executor, cmd, prompt: "fix the bug")
        XCTAssertTrue(mock.launched.isEmpty)   // no terminal launched
        XCTAssertEqual(opened.value?.absoluteString,
                       "cursor://anthropic.claude-code/open?prompt=fix%20the%20bug")
        XCTAssertNoThrow(try result.get())
    }

    // MARK: - Failure paths (the production error model)

    func test_terminalNotInstalled_reportsTypedFailure() {
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        assertFailure(run(exec(FailingLauncher(.notInstalled)), cmd, prompt: "x"),
                      .terminalNotInstalled(.terminalApp))
    }
    func test_terminalAutomationFailure_reportsTypedFailure() {
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        assertFailure(run(exec(FailingLauncher(.automationFailed("denied"))), cmd, prompt: "x"),
                      .terminalAutomationFailed(.terminalApp, "denied"))
    }
    func test_editorDeepLinkRejected_reportsTypedFailure() {
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in MockLauncher() },
                                       openURL: { _ in false })   // no handler claimed the scheme
        let cmd = Command(id: "claude-code", label: "Claude Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"),
                          target: .editor(.cursor), acceptsPrompt: true,
                          editorIntegration: .claudeCode)
        assertFailure(run(executor, cmd, prompt: "x"), .editorDeepLinkRejected(.cursor))
    }
    func test_editorMissingIntegration_failsHonestly_noTerminalFallback() {
        let mock = MockLauncher()
        let opened = Box<URL?>(nil)
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in mock },
                                       openURL: { opened.value = $0; return true })
        let cmd = Command(id: "x", label: "X", triggers: ["x"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"),
                          target: .editor(.cursor), acceptsPrompt: true,
                          editorIntegration: nil)   // no integration data
        let result = run(executor, cmd, prompt: "hi")
        XCTAssertNil(opened.value)                 // no deep link
        XCTAssertTrue(mock.launched.isEmpty)       // and NO silent terminal fallback
        assertFailure(result, .editorIntegrationMissing(.cursor))
    }
    func test_openApp_launchError_reportsTypedFailure() {
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in MockLauncher() },
                                       openApp: { _, done in done(.failure(.appLaunchFailed("boom"))) })
        let cmd = Command(id: "a", label: "App", triggers: [], kind: .openApp(bundleID: "com.x.y"))
        assertFailure(run(executor, cmd, prompt: nil), .appLaunchFailed("boom"))
    }
    func test_runShell_throws_reportsShellFailure() {
        struct Boom: Error {}
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in MockLauncher() },
                                       runShell: { _ in throw Boom() })
        let cmd = Command(id: "s", label: "Sh", triggers: ["t"], kind: .runShell(script: "false"))
        guard case .failure(.shellFailed) = run(executor, cmd, prompt: nil) else {
            return XCTFail("expected .shellFailed")
        }
    }

    // MARK: - Every failure carries user-facing copy

    func test_everyFailure_hasMessageAndIslandLine() {
        let cases: [LaunchFailure] = [
            .terminalNotInstalled(.terminalApp),
            .terminalAutomationFailed(.iterm2, "denied"),
            .editorDeepLinkRejected(.cursor),
            .editorIntegrationMissing(.vscode),
            .appNotFound("com.x.y"),
            .appLaunchFailed("boom"),
            .shellFailed("nope"),
        ]
        for f in cases {
            XCTAssertFalse((f.errorDescription ?? "").isEmpty, "\(f) needs an errorDescription")
            XCTAssertFalse(f.islandMessage.isEmpty, "\(f) needs an islandMessage")
        }
    }
}
