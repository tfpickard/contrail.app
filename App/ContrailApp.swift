import SwiftUI

@main
struct ContrailApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AdaptiveRoot()
                .environment(model)
                .task {
                    model.verifyBundledAssets()
                    model.loadProfile()
                    await model.startMapServer()
                }
        }
    }
}
