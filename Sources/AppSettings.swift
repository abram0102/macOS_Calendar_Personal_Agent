import AppKit
import SwiftUI

enum WindowLayer: String, CaseIterable, Identifiable {
    case desktop, normal, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: return "贴在桌面（壁纸之上、其它窗口之下）"
        case .normal: return "普通窗口"
        case .floating: return "总在最前"
        }
    }
    var level: NSWindow.Level {
        switch self {
        case .desktop:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal:
            return .normal
        case .floating:
            return .floating
        }
    }
}

enum TextScale: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
    var base: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 12.5
        case .large: return 14
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var layer: WindowLayer { didSet { persist("layer", layer.rawValue); onChange?() } }
    @Published var opacity: Double { didSet { persist("opacity", opacity); onChange?() } }
    @Published var scale: TextScale { didSet { persist("scale", scale.rawValue) } }
    @Published var hidePastEvents: Bool { didSet { persist("hidePastEvents", hidePastEvents) } }
    @Published var hideEmptyDays: Bool { didSet { persist("hideEmptyDays", hideEmptyDays) } }
    @Published var showPinnedNote: Bool { didSet { persist("showPinnedNote", showPinnedNote) } }
    @Published var lockPosition: Bool { didSet { persist("lockPosition", lockPosition); onChange?() } }

    /// Lets AppDelegate re-apply level/opacity to the NSWindow when they change
    var onChange: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "layer": WindowLayer.desktop.rawValue,
            "opacity": 0.92,
            "scale": TextScale.medium.rawValue,
            "hidePastEvents": false,
            "hideEmptyDays": false,
            "showPinnedNote": true,
            "lockPosition": false,
        ])
        layer = WindowLayer(rawValue: d.string(forKey: "layer") ?? "") ?? .desktop
        opacity = d.double(forKey: "opacity")
        scale = TextScale(rawValue: d.string(forKey: "scale") ?? "") ?? .medium
        hidePastEvents = d.bool(forKey: "hidePastEvents")
        hideEmptyDays = d.bool(forKey: "hideEmptyDays")
        showPinnedNote = d.bool(forKey: "showPinnedNote")
        lockPosition = d.bool(forKey: "lockPosition")
    }

    private func persist(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
