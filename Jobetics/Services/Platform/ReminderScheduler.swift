import Foundation
import UserNotifications

/// Local reminders computed from private data. They never leave the device.
enum ReminderScheduler {
    private static let prefix = "jobetics.reminder."

    struct Reminder: Hashable {
        var id: String
        var title: String
        var body: String
        var date: Date
    }

    /// Pure planning step, unit tested: which reminders the current data calls for.
    static func plan(missions: [MissionSnapshot], invoices: [InvoiceSnapshot], pipelineCount: Int,
                     warningDays: Int, now: Date = .now) -> [Reminder] {
        var reminders: [Reminder] = []
        for mission in missions where mission.isActive && mission.isLong {
            guard let warn = Calendar.current.date(byAdding: .day, value: -warningDays, to: mission.endDate) else { continue }
            guard pipelineCount == 0 else { continue }
            let date = max(warn, now.addingTimeInterval(60))
            if mission.endDate > now {
                reminders.append(Reminder(
                    id: prefix + "mission-end-" + mission.id,
                    title: String(localized: "\(mission.title) ends soon"),
                    body: String(localized: "Your pipeline is empty. A good moment to look for your next mission, calmly."),
                    date: date))
            }
        }
        for invoice in invoices where invoice.isUnpaid {
            for offset in [1, 15, 30] {
                guard let date = Calendar.current.date(byAdding: .day, value: offset, to: invoice.dueDate), date > now else { continue }
                reminders.append(Reminder(
                    id: prefix + "invoice-\(invoice.number)-\(offset)",
                    title: String(localized: "Invoice \(invoice.number) is overdue"),
                    body: String(localized: "\(invoice.client) hasn't paid yet. Send a reminder from Jobetics."),
                    date: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: date) ?? date))
                break
            }
        }
        return reminders
    }

    static func schedule(_ reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for reminder in reminders.prefix(50) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.interruptionLevel = .passive
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}

nonisolated struct MissionSnapshot: Hashable, Sendable {
    var id: String
    var title: String
    var endDate: Date
    var isActive: Bool
    var isLong: Bool
}

nonisolated struct InvoiceSnapshot: Hashable, Sendable {
    var number: String
    var client: String
    var dueDate: Date
    var isUnpaid: Bool
}
