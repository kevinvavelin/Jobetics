import AppIntents

/// Starts a Pomodoro focus session in Jobetics. Used by the widget button, the
/// Control Center control and Siri / Shortcuts ("Start focus in Jobetics").
nonisolated struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Start a Pomodoro focus session in Jobetics.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedStore.pendingRoute = "focus-start"
        return .result()
    }
}

nonisolated struct JobeticsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start focus in \(.applicationName)", "Start a Pomodoro in \(.applicationName)"],
                    shortTitle: "Start Focus", systemImageName: "timer")
    }
}
