import ActivityKit
import Foundation
import UserNotifications
import WidgetKit

/// Pomodoro timer. Time is derived from `endDate` (never from a ticking counter), so it stays
/// correct when the app is suspended. The end of each phase is announced by a local notification,
/// and the Live Activity keeps the countdown visible on the Lock Screen and Dynamic Island.
@Observable
final class FocusTimer {
    private(set) var session = SharedStore.focusSession
    private(set) var completedToday = SharedStore.focusCompletedToday
    private(set) var minutesToday = SharedStore.focusMinutesToday
    var settings = SharedStore.focusSettings {
        didSet { SharedStore.focusSettings = settings }
    }

    private var completionTask: Task<Void, Never>?
    private var activity: Activity<FocusActivityAttributes>?
    private static let notificationID = "focus.phase.end"

    init() {
        if LaunchOptions.isDemo {
            session = FocusSession()
            completedToday = 0
            minutesToday = 0
            return
        }
        activity = Activity<FocusActivityAttributes>.activities.first
        refresh()
    }

    var phase: FocusPhase { session.phase }
    var progress: Double {
        let total = settings.duration(of: session.phase)
        return session.isIdle ? 0 : 1 - session.remaining() / total
    }
    var dailyProgress: Double { min(1, Double(completedToday) / Double(max(1, settings.dailyGoal))) }

    // MARK: Controls

    func start(_ phase: FocusPhase? = nil, task: String? = nil) {
        if let phase { session.phase = phase }
        if let task { session.taskTitle = task }
        let duration = session.pausedRemaining ?? settings.duration(of: session.phase)
        session.pausedRemaining = nil
        session.startDate = .now
        session.endDate = .now.addingTimeInterval(duration)
        persist()
        scheduleCompletion()
        Task { await updateLiveActivity() }
    }

    func pause() {
        guard session.isRunning else { return }
        session.pausedRemaining = session.remaining()
        session.endDate = nil
        persist()
        cancelCompletion()
        Task { await endLiveActivity() }
    }

    func toggle() { session.isRunning ? pause() : start() }

    func skip() { advance(countingFocus: false) }

    func reset() {
        cancelCompletion()
        session = FocusSession(phase: .focus, cycleCount: session.cycleCount)
        persist()
        Task { await endLiveActivity() }
    }

    /// Call when the app becomes active: completes phases that ended while suspended.
    func refresh() {
        guard !LaunchOptions.isDemo else { return }
        completedToday = SharedStore.focusCompletedToday
        minutesToday = SharedStore.focusMinutesToday
        if session.isRunning, session.remaining() <= 0 {
            advance(countingFocus: true)
        } else if session.isRunning {
            scheduleCompletion()
        }
    }

    // MARK: Phase changes

    private func advance(countingFocus: Bool) {
        cancelCompletion()
        if session.phase == .focus && countingFocus {
            completedToday += 1
            minutesToday += settings.focusMinutes
            SharedStore.focusCompletedToday = completedToday
            SharedStore.focusMinutesToday = minutesToday
        }
        let next = session.nextPhase(settings: settings)
        if session.phase == .focus { session.cycleCount += 1 }
        if next == .longBreak || session.phase == .longBreak { session.cycleCount = next == .longBreak ? session.cycleCount : 0 }
        session.phase = next
        session.startDate = nil
        session.endDate = nil
        session.pausedRemaining = nil
        persist()
        Task { await endLiveActivity() }
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        let remaining = session.remaining()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.advance(countingFocus: true)
        }
        scheduleNotification(after: remaining)
    }

    private func cancelCompletion() {
        completionTask?.cancel()
        completionTask = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func scheduleNotification(after seconds: TimeInterval) {
        guard seconds > 1, !LaunchOptions.isDemo else { return }
        let content = UNMutableNotificationContent()
        if session.phase == .focus {
            content.title = String(localized: "Focus session complete")
            content.body = String(localized: "Great work. Time for a break.")
        } else {
            content.title = String(localized: "Break is over")
            content.body = String(localized: "Ready for the next focus session?")
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["link": "jobetics://focus"]
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            try? await center.add(request)
        }
    }

    private func persist() {
        guard !LaunchOptions.isDemo else { return }
        SharedStore.focusSession = session
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusWidget")
    }

    // MARK: Live Activity

    private func updateLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let start = session.startDate, let end = session.endDate else { return }
        let state = FocusActivityAttributes.ContentState(phase: session.phase, startDate: start, endDate: end, completedToday: completedToday)
        let content = ActivityContent(state: state, staleDate: end)
        if let activity {
            await activity.update(content)
        } else {
            let attributes = FocusActivityAttributes(taskTitle: session.taskTitle, dailyGoal: settings.dailyGoal)
            activity = try? Activity.request(attributes: attributes, content: content)
        }
    }

    private func endLiveActivity() async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    /// Demo values for screenshots.
    /// Demo values for screenshots. Never persisted, so demo data can't leak into real use.
    func loadDemo() {
        cancelCompletion()
        completedToday = 5
        minutesToday = 125
        session = FocusSession(phase: .focus, startDate: .now.addingTimeInterval(-9 * 60 - 18),
                               endDate: .now.addingTimeInterval(15 * 60 + 42), taskTitle: "Audit current app flows", cycleCount: 1)
    }
}
