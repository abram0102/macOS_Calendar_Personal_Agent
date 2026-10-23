import AppKit
import EventKit
import SwiftUI

/// Reads the system Calendar read-only and refreshes itself whenever it changes.
/// Never writes back: there is no save/remove call anywhere in here.
final class CalendarStore: ObservableObject {

    enum Access {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var days: [DeskDay] = []
    @Published private(set) var access: Access = .unknown
    @Published private(set) var lastRefresh: Date? = nil

    @Published var range: DeskRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: "range")
            reload()
        }
    }

    /// Calendar names hidden by the user (toggled from the menu)
    @Published var hiddenCalendars: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenCalendars), forKey: "hiddenCalendars")
            reload()
        }
    }

    @Published private(set) var availableCalendars: [String] = []

    private let store = EKEventStore()
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 2
        return c
    }()
    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.string(forKey: "range") ?? DeskRange.week.rawValue
        range = DeskRange(rawValue: saved) ?? .week
        hiddenCalendars = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])

        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store)

        // Refresh right after the machine wakes up
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(storeChanged),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Safety net: refresh every 5 minutes, which also re-groups the days past midnight
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.reload()
        }
        timer?.tolerance = 60
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func storeChanged() {
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    // MARK: - Authorization

    func requestAccess() {
        if Self.isAuthorized {
            access = .granted
            reload()
            return
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .denied || status == .restricted {
            access = .denied
            return
        }

        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = granted ? .granted : .denied
                if granted { self.reload() }
            }
        }

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Loading

    static var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status.rawValue == 3   // .authorized
    }

    func reload() {
        guard Self.isAuthorized else {
            if access == .granted { access = .unknown }
            return
        }
        access = .granted

        let interval = range.interval(from: Date(), calendar: calendar)
        let cals = store.calendars(for: .event)
        let names = cals.map(\.title).sorted()
        let visible = cals.filter { !hiddenCalendars.contains($0.title) }

        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end,
            calendars: visible.isEmpty ? nil : visible)
        let raw = visible.isEmpty ? [] : store.events(matching: predicate)

        var buckets: [String: [DeskEvent]] = [:]
        for ev in raw {
            guard let start = ev.startDate else { continue }
            let end = ev.endDate ?? start
            let color = Color(nsColor: ev.calendar?.color ?? .systemBlue)
            let baseID = (ev.eventIdentifier ?? ev.calendarItemIdentifier)
                + "|" + String(Int(start.timeIntervalSince1970))

            // A multi-day event shows up on every day it spans
            var cursor = calendar.startOfDay(for: max(start, interval.start))
            let lastDay = calendar.startOfDay(
                for: min(ev.isAllDay ? end.addingTimeInterval(-1) : end,
                         interval.end.addingTimeInterval(-1)))
            repeat {
                let key = DeskFormatters.dayKey.string(from: cursor)
                buckets[key, default: []].append(
                    DeskEvent(id: baseID + "@" + key,
                              title: ev.title ?? "(无标题)",
                              location: (ev.location?.isEmpty == false) ? ev.location : nil,
                              start: start, end: end,
                              isAllDay: ev.isAllDay,
                              calendarTitle: ev.calendar?.title ?? "",
                              calendarColor: color))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            } while cursor <= lastDay
        }

        var result: [DeskDay] = []
        var cursor = interval.start
        while cursor < interval.end {
            let key = DeskFormatters.dayKey.string(from: cursor)
            let events = (buckets[key] ?? []).sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay && !$1.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.title < $1.title
            }
            result.append(DeskDay(date: cursor, key: key, events: events))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        availableCalendars = names
        days = result
        lastRefresh = Date()
    }

    func toggleCalendar(_ name: String) {
        if hiddenCalendars.contains(name) { hiddenCalendars.remove(name) }
        else { hiddenCalendars.insert(name) }
    }

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    func isWeekend(_ date: Date) -> Bool { calendar.isDateInWeekend(date) }

    /// Splits the current range into weeks (Monday first; edge weeks may be shorter)
    var weeks: [DeskWeek] {
        var result: [DeskWeek] = []
        var bucket: [DeskDay] = []
        for day in days {
            if !bucket.isEmpty,
               calendar.component(.weekday, from: day.date) == calendar.firstWeekday {
                result.append(DeskWeek(index: result.count, days: bucket))
                bucket = []
            }
            bucket.append(day)
        }
        if !bucket.isEmpty { result.append(DeskWeek(index: result.count, days: bucket)) }
        return result
    }

    /// Title of the current range, e.g. "October 2026"
    var periodTitle: String {
        DeskFormatters.monthTitle.string(from: days.first?.date ?? Date())
    }

    func day(forKey key: String) -> DeskDay? { days.first(where: { $0.key == key }) }

    var todayKey: String { DeskFormatters.dayKey.string(from: Date()) }
}
