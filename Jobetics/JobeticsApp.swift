//
//  JobeticsApp.swift
//  Jobetics
//
//  Created by Kevin Vavelin on 22/11/2026.
//

import SwiftData
import SwiftUI

@main
struct JobeticsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment: AppEnvironment

    init() {
        // Firebase must be configured before anything touches Auth/Firestore. App.init() runs
        // before the app delegate's didFinishLaunching, so it's configured here, first.
        FirebaseBootstrap.configureIfNeeded()
        _environment = State(initialValue: AppEnvironment.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.store)
                .environment(environment.auth)
                .environment(environment.router)
                .environment(environment.browser)
                .environment(environment.focus)
                .safeBrowsing(environment.browser)
                .onOpenURL { environment.router.handle($0, store: environment.store) }
                .tint(Brand.indigo)
        }
        .modelContainer(environment.container)
    }
}
