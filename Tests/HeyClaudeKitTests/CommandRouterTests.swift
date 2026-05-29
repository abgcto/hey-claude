import XCTest
@testable import HeyClaudeKit

final class CommandRouterTests: XCTestCase {
    private func router() -> CommandRouter {
        CommandRouter(
            defaultAction: .launchCLI(prompt: nil),
            phraseMap: ["open the app": .openDesktopApp])
    }

    func test_silenceUsesDefault() {
        XCTAssertEqual(router().route(transcript: nil), .launchCLI(prompt: nil))
    }

    func test_codeAloneLaunchesCLI() {
        XCTAssertEqual(router().route(transcript: "code"), .launchCLI(prompt: nil))
    }

    func test_configuredPhraseMapsToAction() {
        XCTAssertEqual(router().route(transcript: "open the app"), .openDesktopApp)
    }

    func test_codePrefixCarriesPrompt() {
        XCTAssertEqual(router().route(transcript: "code refactor the auth module"),
                       .launchCLI(prompt: "refactor the auth module"))
    }

    func test_freeformBecomesPrompt() {
        XCTAssertEqual(router().route(transcript: "refactor the auth module"),
                       .launchCLI(prompt: "refactor the auth module"))
    }

    func test_matchingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(router().route(transcript: "  Open The App  "), .openDesktopApp)
    }
}
