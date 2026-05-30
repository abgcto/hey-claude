import Foundation

/// Builds the editor deep link that opens Claude Code (or another tool) inside
/// an editor with the prompt pre-filled. Pure + tool-agnostic: the scheme comes
/// from the editor, the host/path/param from the tool's `EditorIntegration`.
///
/// Produces e.g. `cursor://anthropic.claude-code/open?prompt=fix%20the%20bug`.
public enum DeepLinkBuilder {
    public static func url(editor: EditorKind,
                           integration: EditorIntegration,
                           prompt: String?) -> URL {
        var c = URLComponents()
        c.scheme = editor.urlScheme           // editor: vscode / cursor / antigravity
        c.host   = integration.deepLinkHost   // tool:   anthropic.claude-code
        c.path   = integration.deepLinkPath   // tool:   /open
        if let p = prompt, !p.isEmpty {
            // URLQueryItem percent-encodes the value (spaces, em-dashes, emoji…).
            c.queryItems = [URLQueryItem(name: integration.promptParam, value: p)]
        }
        // Safe: scheme/host/path are controlled constants and the query is
        // encoded by URLComponents. A failure here is a programmer error.
        guard let url = c.url else {
            preconditionFailure("DeepLinkBuilder produced an invalid URL for \(editor)")
        }
        return url
    }
}
