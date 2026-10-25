import SwiftUI

struct MaxActivityApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            model.inject(MenuBarView())
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("MaxActivity")
        }
        .menuBarExtraStyle(.window)
    }
}
