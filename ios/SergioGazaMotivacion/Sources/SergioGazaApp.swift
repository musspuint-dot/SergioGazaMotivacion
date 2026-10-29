import SwiftUI

@main
struct SergioGazaApp: App {
    @StateObject private var store = PhraseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization { granted in
                        if granted && NotificationManager.shared.pendingCount == 0 {
                            store.applyAndScheduleNotifications()
                        }
                    }
                }
        }
    }
}
