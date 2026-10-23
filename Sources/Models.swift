import Foundation
import SwiftUI

extension Notification.Name {
    /// Tells every text field to leave editing state
    static let deskEndEditing = Notification.Name("DeskEndEditing")
}

// MARK: - Display range

enum DeskRange: String, CaseIterable, Identifiable {
    case today = "today"
    case week = "week"
    case month = "month"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "一周"
        case .month: return "本月"
        }
    }

    /// Returns [first day 00:00, last day 24:00)
    func interval(from now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return DateInterval(start: today, end: end)
        case .week:
            let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            return DateInterval(start: today, end: end)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: today)
            let start = calendar.date(from: comps) ?? today
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? today
            return DateInterval(start: start, end: end)
        }
    }
}

// MARK: - Event (read-only snapshot of an EventKit event)

struct DeskEvent: Identifiable, Equatable {
    let id: String            // Stable key: event identifier + start date of this occurrence
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: Color

    static func == (a: DeskEvent, b: DeskEvent) -> Bool {
        a.id == b.id && a.title == b.title && a.start == b.start
            && a.end == b.end && a.isAllDay == b.isAllDay && a.location == b.location
    }

    var timeText: String {
        if isAllDay { return "全天" }
        let f = DeskFormatters.time
        let s = f.string(from: start)
        if end > start.addingTimeInterval(60) {
            return "\(s) – \(f.string(from: end))"
        }
        return s
    }
}

struct DeskDay: Identifiable {
    let date: Date
    let key: String           // yyyy-MM-dd
    var events: [DeskEvent]

    var id: String { key }
}

/// One week inside the month view (the first/last week may be shorter than 7 days)
struct DeskWeek: Identifiable {
    let index: Int
    let days: [DeskDay]

    var id: Int { index }
    var start: Date { days.first?.date ?? Date() }
    var end: Date { days.last?.date ?? Date() }
    var events: [DeskEvent] { days.flatMap(\.events) }

    var rangeText: String {
        let f = DeskFormatters.shortDay
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

// MARK: - Shared formatters

enum DeskFormatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f
    }()
}
