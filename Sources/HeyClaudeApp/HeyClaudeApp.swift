import SwiftUI

/// Hey Claude menu-bar app (Phase 3A). A `MenuBarExtra` that runs the proven
/// voice→launch pipeline, shows live state through its icon, and exposes mute +
/// recent actions + quit.
@main
struct HeyClaudeApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
        } label: {
            // A `.task` on the label boots the pipeline once the scene is live.
            // Driving `start()` from `App.init()` is unreliable under the
            // SwiftUI lifecycle (the `@State` controller isn't guaranteed
            // installed yet); `.task` runs after the view is on screen and
            // `start()` is idempotent, so this fires exactly once.
            Image(nsImage: MenuBarIcon.image(for: controller.state))
                .task { controller.start() }
        }
        .menuBarExtraStyle(.menu)
    }
}
