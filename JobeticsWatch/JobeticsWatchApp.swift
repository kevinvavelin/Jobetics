import SwiftUI

@main
struct JobeticsWatchApp: App {
    @State private var timer = WatchFocusTimer()

    init() { WatchSync.shared.activate() }

    var body: some Scene {
        WindowGroup {
            WatchHomeView().environment(timer)
        }
    }
}

struct WatchHomeView: View {
    var body: some View {
        TabView {
            WatchFocusView()
            WatchMotivationView()
            WatchScoreView()
        }
        .tabViewStyle(.verticalPage)
    }
}
