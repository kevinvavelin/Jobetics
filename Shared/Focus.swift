import Foundation

/// Pomodoro technique: focus sessions separated by short breaks, and a long break every N sessions.
nonisolated enum FocusPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Short break")
        case .longBreak: String(localized: "Long break")
        }
    }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile.fill"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var isBreak: Bool { self != .focus }
}

nonisolated struct FocusSettings: Codable, Hashable, Sendable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var sessionsBeforeLongBreak = 4
    var dailyGoal = 8

    func duration(of phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .focus: TimeInterval(focusMinutes * 60)
        case .shortBreak: TimeInterval(shortBreakMinutes * 60)
        case .longBreak: TimeInterval(longBreakMinutes * 60)
        }
    }
}

/// The running (or paused) session, persisted so it survives app relaunches and is
/// readable by widgets. Running when `endDate != nil`, paused when `pausedRemaining != nil`.
nonisolated struct FocusSession: Codable, Hashable, Sendable {
    var phase: FocusPhase = .focus
    var startDate: Date?
    var endDate: Date?
    var pausedRemaining: TimeInterval?
    var taskTitle: String?
    /// Focus sessions completed in the current cycle (resets after a long break).
    var cycleCount = 0

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isIdle: Bool { !isRunning && !isPaused }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    func nextPhase(settings: FocusSettings) -> FocusPhase {
        guard phase == .focus else { return .focus }
        return (cycleCount + 1) % settings.sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
    }
}

#if os(iOS)
import ActivityKit

/// Live Activity shown on the Lock Screen and in the Dynamic Island while a session runs.
nonisolated struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: FocusPhase
        var startDate: Date
        var endDate: Date
        var completedToday: Int
    }

    var taskTitle: String?
    var dailyGoal: Int
}
#endif
