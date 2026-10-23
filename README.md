# CalendarDesk

A desk-pinned window that shows your calendar and holds your to-dos. It reads the system Calendar
(read-only, auto-refreshing); the to-dos you type live in a local file and are never written back
to the calendar.

- Target: Apple Silicon (M4), macOS 15.x
- Built with Swift 6 + SwiftUI + EventKit, compiled straight with `swiftc` — no Xcode project needed
- The UI is in Chinese (it is a personal tool); the code and docs are in English

## Build / install

```bash
./build.sh install   # build -> install into ~/Applications -> launch
./build.sh           # build only, into build/CalendarDesk.app
```

On first launch macOS asks for calendar access — allow it.
If you denied it by accident: System Settings › Privacy & Security › Calendars › enable CalendarDesk.

## Usage

The app has no Dock icon. You control it from the **calendar icon in the menu bar** and from the
slider button in the window's title bar.

### Display ranges

- **Today** — a single day, scrolling list
- **Week** — the next 7 days from today, scrolling list
- **Month** — the calendar month, as a three-level drill-down:
  `week thumbnails` (date span + item count + a 7-cell density strip)
  → tap a week → `day thumbnails` (date + item count + the first few events)
  → tap a day → `day detail` (full schedule + to-dos)
  `‹` in the top-left goes back one level, "本月" on the right jumps straight back out.

### To-dos and Done

Two things can be ticked off, and both land in the same Done section: to-dos you typed, and the
events pulled in from the calendar.

- A pinned list sits at the top; every day has its own list below its events.
- Type into the dashed field and press **Return** to create a to-do. Each one gets its own box,
  and its text stays editable in place.
- Click the circle on the left — on a to-do box or on a calendar event — to complete it: a **rag
  animation** sweeps a small sponge from left to right, wiping the text away, and the item drops
  into the **Done** section of that day.
- Completing a calendar event is recorded locally only. The event in Calendar is never touched,
  and it reappears as soon as it is restored.
- Done is collapsed by default and shows a count. Rows coming from the calendar carry a coloured
  dot. Every row can be put back (green check) or removed (trash); removing a to-do deletes it,
  while removing an event just takes it out of the window. "清空" clears the whole Done section.
- Events removed this way can all be brought back with "恢复被移除的日程" in the settings menu.
- Everything is saved 0.6s after the last keystroke.

### Event notes

The speech-bubble icon next to an event attaches free text to that event. It is a note, not a
to-do, and it is stored locally — the calendar event itself is never modified.

### Leaving editing state

Clicking anywhere outside a text field, pressing `Esc`, or the window losing focus all end editing
and flush to disk immediately.

### Window

- Levels: pinned to the desktop (default — above the wallpaper, below other windows),
  normal window, or always on top
- Lock position, opacity, text size, hide empty days, hide today's past events, pick which
  calendars to show
- Drag the title bar to move it, drag the edges to resize (both disabled while position is locked)

## Auto-refresh

- Listens for `EKEventStoreChanged`, so edits made in Calendar show up right away
- Refreshes after the machine wakes from sleep
- A 5-minute safety-net poll, plus a re-group when the date rolls over at midnight
- "刷新日程" in the menu bar forces a refresh

## Launch at login

System Settings › General › Login Items › `+` → pick `~/Applications/CalendarDesk.app`

## Where data lives

`~/Library/Application Support/CalendarDesk/notes.json` ("打开备注文件夹" in the menu opens it).
Format v2: `lists` maps a list key (`pinned` or `yyyy-MM-dd`) to an array of items, each with
`text / done / created / completed`; `eventStates` records which calendar events were ticked off
(`done`) or taken out of the window (`hidden`), keyed by event id and pruned after 90 days.
Plain-text notes from v1 are split into one item per line on first launch.

Window frame and preferences live in `UserDefaults` (`com.abram.calendardesk`).

## Files

| File | Role |
|---|---|
| `Sources/main.swift` | NSApplication, desktop-level window, menu bar item |
| `Sources/CalendarStore.swift` | Read-only EventKit access and auto-refresh |
| `Sources/NotesStore.swift` | Local storage for to-dos and notes, debounced saves, v1→v2 migration |
| `Sources/TodoList.swift` | To-do boxes, the reusable rag-wipe animation, Done section |
| `Sources/DeskView.swift` | SwiftUI interface |
| `Sources/AppSettings.swift` | Window level, opacity, text size and other preferences |
| `Sources/Models.swift` | Ranges, event model, formatters |

## Note

The app is ad-hoc signed, so macOS may ask for calendar access again after a rebuild. Just allow it.
