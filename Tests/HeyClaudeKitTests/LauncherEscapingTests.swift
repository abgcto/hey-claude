import XCTest
@testable import HeyClaudeKit

/// Two escaping layers protect terminal launches, and a bug in either lets a
/// spoken prompt break out of its quoting:
///   1. `LaunchSpec.shellCommand()` POSIX single-quotes the dir + prompt.
///   2. The per-terminal AppleScript/keystroke wrappers escape `"` so the
///      command can't terminate the AppleScript string literal early.
/// `TerminalLauncherTests` covers layer 1's single-quote escaping; these tests
/// cover layer 2 (the AppleScript-injection boundary) plus the prompt edge
/// cases that decide whether an arg is emitted at all.
final class LauncherEscapingTests: XCTestCase {

    // MARK: layer 1 — prompt-presence + literal preservation in shellCommand

    func test_shellCommand_emptyPrompt_omitsArg() {
        // An empty transcription must launch a bare `claude`, not `claude ''`.
        let spec = LaunchSpec(directory: "/tmp", executable: "claude", prompt: "")
        XCTAssertEqual(spec.shellCommand(), "cd '/tmp' && claude")
    }

    func test_shellCommand_preservesShellMetacharactersLiterally() {
        // Single-quoting must neutralise $, backticks and ; so the prompt is
        // passed verbatim to claude rather than evaluated by the shell.
        let spec = LaunchSpec(directory: "/tmp", executable: "claude",
                              prompt: "echo $HOME `whoami`; rm -rf x")
        XCTAssertEqual(spec.shellCommand(),
                       "cd '/tmp' && claude 'echo $HOME `whoami`; rm -rf x'")
    }

    // MARK: layer 2 — AppleScript double-quote escaping (injection boundary)

    func test_iterm2_appleScript_escapesDoubleQuotesInPrompt() {
        let script = ITerm2Launcher.appleScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: #"say "hi""#))
        // The embedded command's quotes are backslash-escaped...
        XCTAssertTrue(script.contains(#"claude 'say \"hi\"'"#))
        // ...so the `write text "..."` literal is not terminated early.
        XCTAssertTrue(script.contains(#"write text "cd '/tmp' && claude 'say \"hi\"'""#))
    }

    func test_terminalApp_appleScript_escapesDoubleQuotesInPrompt() {
        let script = TerminalAppLauncher.appleScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: #"say "hi""#))
        XCTAssertTrue(script.contains(#"do script "cd '/tmp' && claude 'say \"hi\"'""#))
    }

    func test_ghostty_keystrokeScript_escapesDoubleQuotesAndPressesReturn() {
        let script = GhosttyLauncher.keystrokeScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: #"say "hi""#))
        XCTAssertTrue(script.contains(#"keystroke "cd '/tmp' && claude 'say \"hi\"'""#))
        XCTAssertTrue(script.contains("key code 36"))   // Return → runs the command
    }

    func test_allWrappers_carryDirectoryAndExecutable() {
        // Smoke-check the happy path for the two AppleScript terminals and
        // Ghostty so a refactor that drops `cd`/executable is caught.
        let spec = LaunchSpec(directory: "/Users/me/proj", executable: "claude", prompt: nil)
        for script in [
            ITerm2Launcher.appleScript(for: spec),
            TerminalAppLauncher.appleScript(for: spec),
            GhosttyLauncher.keystrokeScript(for: spec),
        ] {
            XCTAssertTrue(script.contains("cd '/Users/me/proj' && claude"), script)
        }
    }

    // MARK: regression — apostrophe in prompt (the common voice case)
    //
    // POSIX single-quoting turns `'` into `'\''` — which injects a backslash.
    // AppleScript string literals must escape `\`, so the wrapper has to double
    // it to `\\` BEFORE escaping `"`. A bare `\'` is an invalid AppleScript
    // escape and the whole script fails to compile, so "hey claude, don't break
    // it" used to silently fail every terminal launch. See the osacompile
    // integration test below for the end-to-end guarantee.

    func test_iterm2_appleScript_apostrophePrompt_doublesBackslash() {
        let script = ITerm2Launcher.appleScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: "don't break"))
        XCTAssertTrue(script.contains(#"write text "cd '/tmp' && claude 'don'\\''t break'""#), script)
    }

    func test_terminalApp_appleScript_apostropheInDirectory_doublesBackslash() {
        // Directory paths can contain apostrophes too (/Users/o'brien/…).
        let script = TerminalAppLauncher.appleScript(for:
            LaunchSpec(directory: "/Users/o'brien/proj", executable: "claude", prompt: nil))
        XCTAssertTrue(script.contains(#"do script "cd '/Users/o'\\''brien/proj' && claude""#), script)
    }

    func test_appleScriptLiteral_escapesBackslashBeforeDoubleQuote() {
        // A literal backslash in a prompt must survive as one escaped backslash,
        // not get conflated with the quote-escaping pass.
        let spec = LaunchSpec(directory: "/tmp", executable: "claude", prompt: #"a\b"c"#)
        // shellCommand: cd '/tmp' && claude 'a\b"c'
        // literal:      \ -> \\ , then " -> \"
        XCTAssertEqual(spec.appleScriptLiteral(), #"cd '/tmp' && claude 'a\\b\"c'"#)
    }

    // MARK: integration — generated scripts must actually compile as AppleScript
    //
    // This is the test that would have caught the apostrophe bug. It shells out
    // to /usr/bin/osacompile (present on every macOS) to syntax-check each
    // wrapper's output for the prompts most likely to break quoting. Compile
    // only — nothing is executed, no terminal is opened.

    func test_generatedScripts_compileAsAppleScript_forNastyPrompts() {
        let nasty: [String?] = [
            nil,                        // bare launch
            "don't break it",           // apostrophe -> POSIX '\'' -> backslash
            #"say "hello""#,            // double quotes
            #"it's a "quoted" test"#,   // apostrophe + double quotes
            "echo $HOME `whoami`; ls",  // shell metachars (must stay single-quoted)
            #"path\to\thing"#,          // literal backslashes
        ]
        for prompt in nasty {
            let spec = LaunchSpec(directory: "/Users/o'brien/proj", executable: "claude", prompt: prompt)
            assertCompilesAsAppleScript(ITerm2Launcher.appleScript(for: spec), prompt: prompt)
            assertCompilesAsAppleScript(TerminalAppLauncher.appleScript(for: spec), prompt: prompt)
            assertCompilesAsAppleScript(GhosttyLauncher.keystrokeScript(for: spec), prompt: prompt)
        }
    }

    /// Syntax-checks `script` with `osacompile`, failing the test (with the
    /// compiler error and the offending script) if it does not compile.
    private func assertCompilesAsAppleScript(
        _ script: String, prompt: String?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let tmp = FileManager.default.temporaryDirectory
        let uid = ProcessInfo.processInfo.globallyUniqueString
        let src = tmp.appendingPathComponent("hc-\(uid).applescript")
        let out = tmp.appendingPathComponent("hc-\(uid).scpt")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }

        do { try Data(script.utf8).write(to: src) }
        catch { return XCTFail("temp write failed: \(error)", file: file, line: line) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        proc.arguments = ["-o", out.path, src.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        do { try proc.run() }
        catch { return XCTFail("osacompile launch failed: \(error)", file: file, line: line) }
        proc.waitUntilExit()

        let errText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(
            proc.terminationStatus, 0,
            "AppleScript did not compile for prompt \(prompt.map { "\"\($0)\"" } ?? "nil"):\n\(errText)\n--- script ---\n\(script)",
            file: file, line: line
        )
    }
}
