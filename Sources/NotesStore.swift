import Foundation
import SwiftUI

/// A single to-do item
struct TodoItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var text: String
    var done: Bool = false
    var created: Date = Date()
    var completed: Date? = nil
}

/// Everything typed in the window: to-do lists and event notes.
/// Stored in a local JSON file only; never written back to the system Calendar.
final class NotesStore: ObservableObject {

    /// Key of the pinned list; every other list is keyed by yyyy-MM-dd
    static let pinnedKey = "pinned"

    // All fields optional so older files still decode (synthesized Codable ignores default values)
    private struct Payload: Codable {
        var version: Int?
        var lists: [String: [TodoItem]]?
        var eventNotes: [String: String]?
        // Legacy v1 fields, kept for migration
        var pinned: String?
        var dayNotes: [String: String]?
    }

    @Published private var lists: [String: [TodoItem]] = [:]
    @Published private var eventNotes: [String: String] = [:]

    private let url: URL
    private var saveWork: DispatchWorkItem?

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CalendarDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("notes.json")
        load()
    }

    var storageURL: URL { url }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        lists = payload.lists ?? [:]
        eventNotes = payload.eventNotes ?? [:]

        // v1 plain-text notes -> one to-do per line
        if (payload.version ?? 1) < 2 {
            if let pinned = payload.pinned, !pinned.isEmpty {
                lists[Self.pinnedKey] = Self.split(pinned)
            }
            for (key, text) in payload.dayNotes ?? [:] where !text.isEmpty {
                lists[key] = Self.split(text)
            }
            saveNow()
        }
    }

    private static func split(_ text: String) -> [TodoItem] {
        text.split(whereSeparator: \.isNewline)
            .map { TodoItem(text: String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
    }

    /// Debounced while typing: writes to disk 0.6s after the last keystroke
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let payload = Payload(version: 2, lists: lists, eventNotes: eventNotes,
                              pinned: nil, dayNotes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - To-dos

    func todos(_ key: String) -> [TodoItem] {
        (lists[key] ?? []).filter { !$0.done }.sorted { $0.created < $1.created }
    }

    func doneTodos(_ key: String) -> [TodoItem] {
        (lists[key] ?? []).filter(\.done)
            .sorted { ($0.completed ?? $0.created) > ($1.completed ?? $1.created) }
    }

    func hasTodos(_ key: String) -> Bool { !(lists[key] ?? []).isEmpty }
    func todoCount(_ key: String) -> Int { todos(key).count }

    @discardableResult
    func add(_ key: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        lists[key, default: []].append(TodoItem(text: trimmed))
        scheduleSave()
        return true
    }

    func setDone(_ key: String, id: String, done: Bool) {
        guard var items = lists[key], let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done = done
        items[i].completed = done ? Date() : nil
        lists[key] = items
        saveNow()
    }

    func delete(_ key: String, id: String) {
        lists[key]?.removeAll { $0.id == id }
        if lists[key]?.isEmpty == true { lists.removeValue(forKey: key) }
        saveNow()
    }

    func clearDone(_ key: String) {
        lists[key]?.removeAll(where: \.done)
        if lists[key]?.isEmpty == true { lists.removeValue(forKey: key) }
        saveNow()
    }

    /// The text of a to-do can be edited in place
    func todoText(_ key: String, _ id: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.lists[key]?.first(where: { $0.id == id })?.text ?? ""
            },
            set: { [weak self] value in
                guard let self, var items = self.lists[key],
                      let i = items.firstIndex(where: { $0.id == id }) else { return }
                items[i].text = value
                self.lists[key] = items
                self.scheduleSave()
            })
    }

    // MARK: - Event notes (free text attached to one calendar event)

    func eventNote(_ key: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.eventNotes[key] ?? "" },
            set: { [weak self] value in
                guard let self else { return }
                if value.isEmpty { self.eventNotes.removeValue(forKey: key) }
                else { self.eventNotes[key] = value }
                self.scheduleSave()
            })
    }

    func hasEventNote(_ key: String) -> Bool { !(eventNotes[key] ?? "").isEmpty }
}
