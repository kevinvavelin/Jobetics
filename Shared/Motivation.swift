import Foundation

/// One motivational line per day, the same on iPhone, iPad, widgets and Apple Watch.
nonisolated enum Motivation {
    static let lines: [String] = [
        "Small, finished work beats big, perfect plans.",
        "Reply fast, deliver on time. Trust compounds.",
        "Your next client is reading your portfolio right now.",
        "Ship one thing today you're proud to sign.",
        "Clear scope, fair price, calm mind.",
        "Every invoice sent is a promise kept.",
        "Rest is part of the work. Take a walk.",
        "Say no to vague briefs. Say yes to clear ones.",
        "Consistency is the most underrated skill.",
        "Raise your rate when your calendar is full.",
        "The best follow-up is the one you send today.",
        "Do the hard task first. The rest gets lighter.",
        "Great work is remembered. Being on time is too.",
        "You're not alone. You're independent.",
        "One more step towards the business you want.",
        "Done is a feature. Ship it.",
        "Protect your focus like it pays the bills. It does.",
        "Every review is a reference you'll keep forever.",
        "Write the proposal you'd want to receive.",
        "A five-minute walk can fix a two-hour bug.",
        "Celebrate the small wins. They add up.",
        "Your craft is your brand. Keep sharpening it.",
        "Show up. Reply. Deliver. Repeat.",
        "Good clients are found. Great clients are kept.",
        "Today is a great day to update your portfolio.",
        "Take the meeting. Be two minutes early.",
        "Price the value, not the hours.",
        "Momentum loves a to-do list with three items.",
        "Learn one new thing. Bill for it next month.",
        "You built this. Keep going.",
        "Kind words, clear invoices, happy clients.",
    ]

    /// Lines are keys in the String Catalog (Shared/Localizable.xcstrings), translated in FR and ES.
    static func line(for date: Date = .now, calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return String(localized: String.LocalizationValue(lines[day % lines.count]))
    }
}
