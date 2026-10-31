import SwiftUI

@main
struct LogsperityApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.brandBlue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
    }
}
