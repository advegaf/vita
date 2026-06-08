import SwiftUI
import SwiftData

@main
struct VitaApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let c = VitaContainer.make()
        CatalogStore.bootstrap(c.mainContext) // idempotent first-launch seed
        KeychainSeeder.seedIfNeeded()         // copy embedded key (if any) into Keychain once
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_DEMO_STACK"] == "1" {
            DemoSeed.populate(c.mainContext)
        }
        if let v = ProcessInfo.processInfo.environment["VITA_DIARY_DEMO"] {
            DiaryDemoSeed.populate(c.mainContext, logToday: v == "2")
        }
        if ProcessInfo.processInfo.environment["VITA_LABS_DEMO"] == "1" {
            LabDemoSeed.populate(c.mainContext)
        }
        #endif
        container = c
        NotificationRouter.shared.container = c
        NotificationRouter.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationManager.rebuild(context: container.mainContext)
            }
        }
    }
}
