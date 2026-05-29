/// What a detected wake + (optional) transcript resolves to.
public enum Action: Equatable {
    case launchCLI(prompt: String?)
    case openDesktopApp
    case custom(id: String)
}
