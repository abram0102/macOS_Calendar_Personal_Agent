import AppKit
import Combine
import SwiftUI

// MARK: - Blurred background

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// An area you can press and drag to move the whole window
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        var locked = false
        override func mouseDown(with event: NSEvent) {
            guard !locked else { return }
            window?.performDrag(with: event)
        }
        override func mouseDragged(with event: NSEvent) {
            guard !locked else { return }
            window?.performDrag(with: event)
        }
    }
    var locked: Bool
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.locked = locked }
}

// MARK: - Root view

struct DeskView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var settings: AppSettings

    private var base: CGFloat { settings.scale.base }

    var body: some View {
        ZStack {
            VisualEffect()
            Color.black.opacity(0.18)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: Title bar

    private var header: some View {
        ZStack {
            WindowDragArea(locked: settings.lockPosition)
            HStack(spacing: 8) {
                Text("日程")
                    .font(.system(size: base + 2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Picker("", selection: Binding(
                    get: { store.range },
                    set: { store.range = $0 })) {
                        ForEach(DeskRange.allCases) { r in Text(r.title).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 165)
                    .controlSize(.small)

                Spacer(minLength: 4)

                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("立即刷新")

                SettingsMenu(store: store, notes: notes, settings: settings)
                    .frame(width: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.white.opacity(0.75))
        }
        .frame(height: 36)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .granted:
            if store.range == .month {
                MonthBrowser(store: store, notes: notes, settings: settings, base: base)
            } else {
                list
            }
        case .denied:
            permissionBox(denied: true)
        case .unknown:
            permissionBox(denied: false)
        }
    }

    private func permissionBox(denied: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 26))
            Text(denied ? "没有日历访问权限" : "需要访问「日历」")
                .font(.system(size: base + 1, weight: .semibold))
            Text(denied
                 ? "到「系统设置 › 隐私与安全性 › 日历」里允许 CalendarDesk，然后重开一次。"
                 : "首次运行需要授权，才能读取你的日程。")
                .font(.system(size: base - 1))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            Button(denied ? "打开系统设置" : "请求访问") {
                if denied { store.openPrivacySettings() } else { store.requestAccess() }
            }
            .controlSize(.small)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleDays: [DeskDay] {
        let now = Date()
        return store.days.compactMap { day in
            var d = day
            if settings.hidePastEvents, store.isToday(d.date) {
                d.events = d.events.filter { $0.isAllDay || $0.end >= now }
            }
            if settings.hideEmptyDays,
               d.events.isEmpty,
               !notes.hasTodos(d.key),
               !store.isToday(d.date) {
                return nil
            }
            return d
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    if settings.showPinnedNote {
                        pinnedNote
                    }
                    ForEach(visibleDays) { day in
                        DaySection(day: day, store: store, notes: notes, base: base)
                            .id(day.key)
                    }
                    if let t = store.lastRefresh {
                        Text("更新于 \(DeskFormatters.time.string(from: t))")
                            .font(.system(size: base - 2.5))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear {
                if let today = store.days.first(where: { store.isToday($0.date) }) {
                    proxy.scrollTo(today.key, anchor: .top)
                }
            }
        }
    }

    private var pinnedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("置顶待办", systemImage: "pin.fill")
                .font(.system(size: base - 2, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.8))
            TodoListView(listKey: NotesStore.pinnedKey, accent: .yellow,
                         notes: notes, base: base)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.10))
        )
    }
}

// MARK: - A single day

private struct DaySection: View {
    let day: DeskDay
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    private var isToday: Bool { store.isToday(day.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(DeskFormatters.dayTitle.string(from: day.date))
                    .font(.system(size: base, weight: .semibold))
                Text(DeskFormatters.weekday.string(from: day.date))
                    .font(.system(size: base - 2))
                    .foregroundStyle(.white.opacity(store.isWeekend(day.date) ? 0.75 : 0.45))
                if isToday {
                    Text("今天")
                        .font(.system(size: base - 3, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                }
                Spacer()
            }
            .foregroundStyle(isToday ? .white : .white.opacity(0.82))

            if day.events.isEmpty {
                Text("—")
                    .font(.system(size: base - 1))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.leading, 2)
            } else {
                ForEach(day.events) { ev in
                    EventRow(event: ev, notes: notes, base: base)
                }
            }

            TodoListView(listKey: day.key, notes: notes, base: base)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isToday ? 0.10 : 0.045))
        )
        .overlay(alignment: .leading) {
            if isToday {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
    }
}

private struct EventRow: View {
    let event: DeskEvent
    @ObservedObject var notes: NotesStore
    let base: CGFloat
    @State private var showNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(event.calendarColor)
                    .frame(width: 6, height: 6)
                    .offset(y: -1)
                Text(event.timeText)
                    .font(.system(size: base - 1.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: base * 7.8, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: base))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                    if let loc = event.location {
                        Text(loc)
                            .font(.system(size: base - 2.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    showNote.toggle()
                } label: {
                    Image(systemName: notes.hasEventNote(event.id)
                          ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: base - 2))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(notes.hasEventNote(event.id) ? 0.7 : 0.3))
                .help("给这条日程加备注（不会写回日历）")
            }
            if showNote || notes.hasEventNote(event.id) {
                NoteEditor(text: notes.eventNote(event.id),
                           placeholder: "备注…",
                           base: base - 0.5,
                           minHeight: 22)
                    .padding(.leading, base * 8.9)
            }
        }
        .padding(.vertical, 1)
        .help("\(event.calendarTitle)")
    }
}

// MARK: - Editable text

struct NoteEditor: View {
    @Binding var text: String
    let placeholder: String
    let base: CGFloat
    let minHeight: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(focused ? 0.28 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 0.25 : 0.07), lineWidth: 1)
                )
            if text.isEmpty && !focused {
                Text(placeholder)
                    .font(.system(size: base - 1.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: base - 0.5))
                .foregroundStyle(.white.opacity(0.92))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($focused)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .frame(minHeight: minHeight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: minHeight)
        .onReceive(NotificationCenter.default.publisher(for: .deskEndEditing)) { _ in
            if focused { focused = false }
        }
    }
}

// MARK: - Month: week thumbnails -> day thumbnails -> day detail

private enum MonthLevel: Equatable {
    case weeks
    case days(Int)       // week index
    case day(String)     // yyyy-MM-dd
}

struct MonthBrowser: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var settings: AppSettings
    let base: CGFloat

    @State private var level: MonthLevel = .weeks

    private var weeks: [DeskWeek] { store.weeks }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider().opacity(0.18)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    switch level {
                    case .weeks:
                        ForEach(weeks) { week in
                            WeekCard(week: week, store: store, notes: notes, base: base)
                                .onTapGesture { go(.days(week.index)) }
                        }
                    case .days(let index):
                        if let week = weeks.first(where: { $0.index == index }) {
                            ForEach(week.days) { day in
                                DayCard(day: day, store: store, notes: notes, base: base)
                                    .onTapGesture { go(.day(day.key)) }
                            }
                        }
                    case .day(let key):
                        if let day = store.day(forKey: key) {
                            DaySection(day: filtered(day), store: store,
                                       notes: notes, base: base)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: level)
        .onChange(of: store.range) { _, _ in level = .weeks }
    }

    private func go(_ next: MonthLevel) { level = next }

    private func back() {
        switch level {
        case .weeks:
            break
        case .days:
            level = .weeks
        case .day(let key):
            if let i = weeks.first(where: { w in w.days.contains(where: { $0.key == key }) })?.index {
                level = .days(i)
            } else {
                level = .weeks
            }
        }
    }

    private func filtered(_ day: DeskDay) -> DeskDay {
        guard settings.hidePastEvents, store.isToday(day.date) else { return day }
        var d = day
        let now = Date()
        d.events = d.events.filter { $0.isAllDay || $0.end >= now }
        return d
    }

    // MARK: Breadcrumb and back

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            if level != .weeks {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: base - 1, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("返回上一层")
            }

            Text(title)
                .font(.system(size: base, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            if level != .weeks {
                Button("本月") { level = .weeks }
                    .buttonStyle(.plain)
                    .font(.system(size: base - 2))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text("\(store.days.flatMap(\.events).count) 项")
                    .font(.system(size: base - 2))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var title: String {
        switch level {
        case .weeks:
            return store.periodTitle
        case .days(let i):
            return weeks.first(where: { $0.index == i })?.rangeText ?? store.periodTitle
        case .day(let key):
            guard let day = store.day(forKey: key) else { return store.periodTitle }
            return DeskFormatters.dayTitle.string(from: day.date)
                + " " + DeskFormatters.weekday.string(from: day.date)
        }
    }
}

/// Thumbnail card for one week
private struct WeekCard: View {
    let week: DeskWeek
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    private var containsToday: Bool { week.days.contains { store.isToday($0.date) } }
    private var noteCount: Int { week.days.filter { notes.hasTodos($0.key) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("第 \(week.index + 1) 周")
                    .font(.system(size: base - 2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(week.rangeText)
                    .font(.system(size: base, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                if containsToday {
                    Text("本周")
                        .font(.system(size: base - 3, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 4)
                if noteCount > 0 {
                    Label("\(noteCount)", systemImage: "square.and.pencil")
                        .font(.system(size: base - 3))
                        .foregroundStyle(.yellow.opacity(0.7))
                }
                Text("\(week.events.count) 项")
                    .font(.system(size: base - 2).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                Image(systemName: "chevron.right")
                    .font(.system(size: base - 3, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Seven-cell density strip for the week
            HStack(spacing: 3) {
                ForEach(week.days) { day in
                    VStack(spacing: 2) {
                        Text(DeskFormatters.weekday.string(from: day.date)
                            .replacingOccurrences(of: "周", with: ""))
                            .font(.system(size: base - 4))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.system(size: base - 2, weight: store.isToday(day.date) ? .bold : .regular)
                                .monospacedDigit())
                            .foregroundStyle(.white.opacity(store.isToday(day.date) ? 0.95 : 0.6))
                        HStack(spacing: 1.5) {
                            ForEach(Array(day.events.prefix(3).enumerated()), id: \.offset) { _, ev in
                                Circle().fill(ev.calendarColor).frame(width: 3.5, height: 3.5)
                            }
                            if day.events.count > 3 {
                                Circle().fill(Color.white.opacity(0.35))
                                    .frame(width: 3.5, height: 3.5)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(store.isToday(day.date) ? 0.14 : 0.05))
                    )
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(containsToday ? 0.10 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Thumbnail card for one day (inside the week level)
private struct DayCard: View {
    let day: DeskDay
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    private var isToday: Bool { store.isToday(day.date) }

    private var summary: String {
        if day.events.isEmpty { return notes.hasTodos(day.key) ? "（有待办）" : "没有日程" }
        return day.events.prefix(3).map { ev in
            (ev.isAllDay ? "" : DeskFormatters.time.string(from: ev.start) + " ") + ev.title
        }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 9) {
            VStack(spacing: 0) {
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.system(size: base + 5, weight: .semibold).monospacedDigit())
                Text(DeskFormatters.weekday.string(from: day.date))
                    .font(.system(size: base - 3))
                    .foregroundStyle(.white.opacity(store.isWeekend(day.date) ? 0.7 : 0.4))
            }
            .frame(width: base * 2.6)
            .foregroundStyle(.white.opacity(isToday ? 0.95 : 0.8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isToday {
                        Text("今天")
                            .font(.system(size: base - 3, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                            .foregroundStyle(.white)
                    }
                    HStack(spacing: 2) {
                        ForEach(Array(day.events.prefix(6).enumerated()), id: \.offset) { _, ev in
                            Circle().fill(ev.calendarColor).frame(width: 4, height: 4)
                        }
                    }
                    if notes.hasTodos(day.key) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: base - 3))
                            .foregroundStyle(.yellow.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Text(day.events.isEmpty ? "" : "\(day.events.count) 项")
                        .font(.system(size: base - 3).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text(summary)
                    .font(.system(size: base - 2))
                    .foregroundStyle(.white.opacity(day.events.isEmpty ? 0.3 : 0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: base - 3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isToday ? 0.10 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Settings menu

struct SettingsMenu: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Menu {
            Section("窗口") {
                Picker("层级", selection: $settings.layer) {
                    ForEach(WindowLayer.allCases) { Text($0.title).tag($0) }
                }
                Toggle("锁定位置", isOn: $settings.lockPosition)
                Picker("不透明度", selection: $settings.opacity) {
                    Text("60%").tag(0.6)
                    Text("75%").tag(0.75)
                    Text("92%").tag(0.92)
                    Text("100%").tag(1.0)
                }
                Picker("字号", selection: $settings.scale) {
                    ForEach(TextScale.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("内容") {
                Toggle("显示置顶备注", isOn: $settings.showPinnedNote)
                Toggle("隐藏今天已过去的日程", isOn: $settings.hidePastEvents)
                Toggle("隐藏空白日期", isOn: $settings.hideEmptyDays)
            }
            if !store.availableCalendars.isEmpty {
                Section("日历") {
                    ForEach(store.availableCalendars, id: \.self) { name in
                        Button {
                            store.toggleCalendar(name)
                        } label: {
                            Text((store.hiddenCalendars.contains(name) ? "  " : "✓ ") + name)
                        }
                    }
                }
            }
            Divider()
            Button("打开备注文件夹") {
                NSWorkspace.shared.activateFileViewerSelecting([notes.storageURL])
            }
            Button("退出 CalendarDesk") {
                notes.saveNow()
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
