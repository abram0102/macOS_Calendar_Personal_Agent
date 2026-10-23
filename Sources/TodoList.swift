import AppKit
import SwiftUI

// MARK: - One list: to-dos plus the Done section below them

struct TodoListView: View {
    let listKey: String
    var accent: Color = .white
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    @State private var draft: String = ""
    @State private var doneExpanded = false
    @FocusState private var addFocused: Bool

    private var items: [TodoItem] { notes.todos(listKey) }
    private var done: [TodoItem] { notes.doneTodos(listKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                TodoBox(listKey: listKey, item: item, notes: notes, base: base, accent: accent)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))))
            }

            addRow

            if !done.isEmpty {
                doneSection
            }
        }
        .animation(.easeInOut(duration: 0.22), value: items.map(\.id))
        .animation(.easeInOut(duration: 0.22), value: done.map(\.id))
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
                        Text("\(done.count)")
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
                        withAnimation { notes.clearDone(listKey) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: base - 3))
                    .foregroundStyle(.white.opacity(0.35))
                    .help("删除这份清单里所有已完成项")
                }
            }
            .padding(.top, 2)

            if doneExpanded {
                ForEach(done) { item in
                    DoneRow(listKey: listKey, item: item, notes: notes, base: base)
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

    private let wipeDuration = 0.5

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
                .mask(
                    GeometryReader { g in
                        Rectangle()
                            .frame(width: max(0, g.size.width * (1 - wipe)))
                            .offset(x: g.size.width * wipe)
                    }
                )

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
        .overlay(ragOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func complete() {
        guard !wiping else { return }
        editing = false
        wiping = true
        withAnimation(.easeInOut(duration: wipeDuration)) { wipe = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + wipeDuration + 0.05) {
            withAnimation(.easeInOut(duration: 0.22)) {
                notes.setDone(listKey, id: item.id, done: true)
            }
        }
    }

    /// The rag: a small sponge sweeping left to right, leaving a fading wet streak behind it
    @ViewBuilder
    private var ragOverlay: some View {
        if wiping {
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
                        .offset(y: sin(wipe * .pi * 3) * 1.6)   // scrub back and forth a couple of times
                }
                .frame(height: g.size.height)
                .offset(x: g.size.width * wipe - (base + 8) / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - One completed item

private struct DoneRow: View {
    let listKey: String
    let item: TodoItem
    @ObservedObject var notes: NotesStore
    let base: CGFloat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button {
                withAnimation { notes.setDone(listKey, id: item.id, done: false) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: base - 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green.opacity(0.55))
            .help("放回待办")

            Text(item.text)
                .font(.system(size: base - 1.5))
                .strikethrough(true, color: .white.opacity(0.3))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)

            Spacer(minLength: 4)

            if let t = item.completed {
                Text(DeskFormatters.time.string(from: t))
                    .font(.system(size: base - 3.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.25))
            }

            Button {
                withAnimation { notes.delete(listKey, id: item.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: base - 3))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(hovering ? 0.65 : 0.3))
            .help("删除这条")
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
