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
