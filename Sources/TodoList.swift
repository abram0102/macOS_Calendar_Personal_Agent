import AppKit
import SwiftUI

// MARK: - The rag wipe

/// Sweeps a small sponge across the view from left to right, wiping its content
/// away as it goes and leaving a fading wet streak behind.
struct RagWipe: ViewModifier {
    let progress: CGFloat
    let active: Bool
    let base: CGFloat

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { g in
                    Rectangle()
                        .frame(width: max(0, g.size.width * (1 - progress)))
                        .offset(x: g.size.width * progress)
                }
            )
            .overlay(sponge)
    }

    @ViewBuilder
    private var sponge: some View {
        if active {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    // The wet streak just wiped
                    LinearGradient(colors: [.clear, .white.opacity(0.16), .white.opacity(0.05)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 34, height: g.size.height)
                        .offset(x: -34)

                    // The sponge itself
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.62, green: 0.84, blue: 0.88),
                                     Color(red: 0.28, green: 0.52, blue: 0.62)],
                            startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                        )
                        .frame(width: base + 8, height: base + 2)
                        .rotationEffect(.degrees(-9))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(y: sin(progress * .pi * 3) * 1.6)   // scrub back and forth
                }
                .frame(height: g.size.height)
                .offset(x: g.size.width * progress - (base + 8) / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func ragWipe(progress: CGFloat, active: Bool, base: CGFloat) -> some View {
        modifier(RagWipe(progress: progress, active: active, base: base))
    }
}

/// Plays the wipe, then runs `completion` (animated) once the sponge is through.
func performRagWipe(progress: Binding<CGFloat>,
                    active: Binding<Bool>,
                    duration: Double = 0.5,
                    completion: @escaping () -> Void) {
    guard !active.wrappedValue else { return }
    active.wrappedValue = true
    withAnimation(.easeInOut(duration: duration)) { progress.wrappedValue = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
        withAnimation(.easeInOut(duration: 0.22)) { completion() }
    }
}

// MARK: - One finished thing, whatever it came from

/// A row under Done. It is either a to-do typed in the window or a calendar
/// event that was ticked off; the actions differ, so they come in as closures.
struct DoneEntry: Identifiable {
    let id: String
    let text: String
    let completed: Date?
    let dot: Color?            // nil for a typed to-do, calendar colour for an event
    let restore: () -> Void
    let remove: () -> Void
    let removeHelp: String
}

// MARK: - One list: to-dos, the day's events, and the Done section below them

struct TodoListView: View {
    let listKey: String
    var accent: Color = .white
    /// The events of this day, so they can be ticked off alongside the to-dos
    var events: [DeskEvent] = []
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    @State private var draft: String = ""
    @State private var doneExpanded = false
    @FocusState private var addFocused: Bool

    private var items: [TodoItem] { notes.todos(listKey) }

    private var doneEntries: [DoneEntry] {
        let todos = notes.doneTodos(listKey).map { item in
            DoneEntry(id: "todo:" + item.id,
                      text: item.text,
                      completed: item.completed,
                      dot: nil,
                      restore: { notes.setDone(listKey, id: item.id, done: false) },
                      remove: { notes.delete(listKey, id: item.id) },
                      removeHelp: "删除这条")
        }
        let fromCalendar = notes.doneEvents(events).map { ev in
            DoneEntry(id: "event:" + ev.id,
                      text: ev.title,
                      completed: notes.completedAt(ev.id),
                      dot: ev.calendarColor,
                      restore: { notes.setEventDone(ev.id, day: listKey, done: false) },
                      remove: { notes.hideEvent(ev.id, day: listKey) },
                      removeHelp: "从窗口里移除（日历中的日程不受影响）")
        }
        return (todos + fromCalendar)
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                TodoBox(listKey: listKey, item: item, notes: notes, base: base, accent: accent)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))))
            }

            addRow

            if !doneEntries.isEmpty {
                doneSection
            }
        }
        .animation(.easeInOut(duration: 0.22), value: items.map(\.id))
        .animation(.easeInOut(duration: 0.22), value: doneEntries.map(\.id))
    }

    // MARK: New item

    private var addRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: base - 3, weight: .bold))
                .foregroundStyle(.white.opacity(addFocused ? 0.55 : 0.28))
            TextField("", text: $draft, prompt:
                        Text("输入待办，回车新建…")
                            .foregroundColor(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: base - 0.5))
                .foregroundStyle(.white.opacity(0.9))
                .focused($addFocused)
                .onSubmit {
                    if notes.add(listKey, text: draft) { draft = "" }
                    addFocused = true
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.white.opacity(addFocused ? 0.25 : 0.10))
        )
    }

    // MARK: Done

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { doneExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: base - 4, weight: .bold))
                            .rotationEffect(.degrees(doneExpanded ? 90 : 0))
                        Text("Done")
                            .font(.system(size: base - 2, weight: .semibold))
                        Text("\(doneEntries.count)")
                            .font(.system(size: base - 3).monospacedDigit())
                            .padding(.horizontal, 4).padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))

                Spacer()

                if doneExpanded {
                    Button("清空") {
                        withAnimation {
                            notes.clearDone(listKey,
                                            eventIDs: notes.doneEvents(events).map(\.id))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: base - 3))
                    .foregroundStyle(.white.opacity(0.35))
                    .help("清空这份 Done：手写待办删除，日历日程从窗口里移除")
                }
            }
            .padding(.top, 2)

            if doneExpanded {
                ForEach(doneEntries) { entry in
                    DoneRow(entry: entry, base: base)
                        .transition(.opacity)
                }
            }
        }
        .padding(.top, 1)
    }
}

// MARK: - To-do box, including the rag-wipe animation

private struct TodoBox: View {
    let listKey: String
    let item: TodoItem
    @ObservedObject var notes: NotesStore
    let base: CGFloat
    let accent: Color

    @State private var wipe: CGFloat = 0
    @State private var wiping = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button(action: complete) {
                Image(systemName: "circle")
                    .font(.system(size: base, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent.opacity(0.5))
            .disabled(wiping)
            .help("完成 → 擦掉并归入 Done")

            TextField("", text: notes.todoText(listKey, item.id), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: base - 0.5))
                .foregroundStyle(.white.opacity(0.92))
                .focused($editing)
                .disabled(wiping)
                .ragWipe(progress: wipe, active: wiping, base: base)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(editing ? 0.26 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(editing ? 0.22 : 0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func complete() {
        editing = false
        performRagWipe(progress: $wipe, active: $wiping) {
            notes.setDone(listKey, id: item.id, done: true)
        }
    }
}

// MARK: - One completed row

private struct DoneRow: View {
    let entry: DoneEntry
    let base: CGFloat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: { withAnimation { entry.restore() } }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: base - 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green.opacity(0.55))
            .help("放回待办")

            if let dot = entry.dot {
                Circle()
                    .fill(dot.opacity(0.65))
                    .frame(width: 5, height: 5)
                    .help("来自日历")
            }

            Text(entry.text)
                .font(.system(size: base - 1.5))
                .strikethrough(true, color: .white.opacity(0.3))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)

            Spacer(minLength: 4)

            if let t = entry.completed {
                Text(DeskFormatters.time.string(from: t))
                    .font(.system(size: base - 3.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.25))
            }

            Button(action: { withAnimation { entry.remove() } }) {
                Image(systemName: "trash")
                    .font(.system(size: base - 3))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(hovering ? 0.65 : 0.3))
            .help(entry.removeHelp)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0.025))
        )
        .onHover { hovering = $0 }
    }
}
