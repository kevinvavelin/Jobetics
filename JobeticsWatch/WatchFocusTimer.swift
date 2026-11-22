import Foundation
import UserNotifications
import WatchKit

/// Pomodoro on Apple Watch: end-date based, with haptics and a notification when a phase ends.
@Observable
final class WatchFocusTimer {
    private(set) var session = FocusSession()
    private(set) var completedToday = SharedStore.focusCompletedToday
    let settings = FocusSettings()
    private var task: Task<Void, Never>?

    var total: TimeInterval { settings.duration(of: session.phase) }

    func toggle() {
        if session.isRunning {
            session.pausedRemaining = session.remaining()
            session.endDate = nil
            task?.cancel()
            WKInterfaceDevice.current().play(.stop)
        } else {
            let duration = session.pausedRemaining ?? total
            session.pausedRemaining = nil
            session.startDate = .now
            session.endDate = .now.addingTimeInterval(duration)
            WKInterfaceDevice.current().play(.start)
            schedule(after: duration)
        }
    }

    func skip() { finish(counting: false) }

    private func schedule(after seconds: TimeInterval) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(counting: true)
        }
        let content = UNMutableNotificationContent()
        content.title = session.phase == .focus ? String(localized: "Focus session complete") : String(localized: "Break is over")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "watch.focus", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func finish(counting: Bool) {
        task?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["watch.focus"])
        if counting && session.phase == .focus {
            completedToday += 1
            SharedStore.focusCompletedToday = completedToday
        }
        let next = session.nextPhase(settings: settings)
        if session.phase == .focus { session.cycleCount += 1 }
        session = FocusSession(phase: next, cycleCount: next == .focus && session.phase == .longBreak ? 0 : session.cycleCount)
        WKInterfaceDevice.current().play(counting ? .success : .click)
    }
}
