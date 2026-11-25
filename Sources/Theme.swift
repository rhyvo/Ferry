import AppKit
import SwiftUI

enum Theme {
    static let key = "themeColor"

    static func color(_ stored: String) -> Color? {
        let parts = stored.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2])
    }

    @MainActor static func tint(_ stored: String) -> Color? {
        SystemAccent.use(stored)
        return color(stored) ?? (SystemAccent.themed ? SystemAccent.macAccent.map { Color(nsColor: $0) } : nil)
    }

    static func encode(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { String(format: "%.4f", $0) }.joined(separator: " ")
    }
}

enum SystemAccent {
    private(set) static var override: NSColor?
    private(set) static var macAccent: NSColor?
    private static var installed = false
    private static var reading = false
    private static var stored = ""
    private static let tintSelector = NSSelectorFromString("appearanceByApplyingTintColor:")

    @MainActor static func install() {
        guard !installed,
              let original = class_getClassMethod(NSColor.self, #selector(getter: NSColor.controlAccentColor)),
              let replacement = class_getClassMethod(NSColor.self, #selector(getter: NSColor.ferryControlAccentColor)) else { return }
        macAccent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        method_exchangeImplementations(original, replacement)
        installed = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("AppleColorPreferencesChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                reading = true
                defer { reading = false }
                if let base = NSAppearance(named: .aqua),
                   let mac = base.perform(NSSelectorFromString("tintColor"))?.takeUnretainedValue() as? NSColor {
                    macAccent = mac.usingColorSpace(.sRGB) ?? macAccent
                }
                apply(stored, force: true)
            }
        }
        center.addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply(stored, force: true) }
        }
        apply(UserDefaults.standard.string(forKey: Theme.key) ?? "", force: true)
    }

    static var answer: NSColor {
        let color = ((reading ? nil : override) ?? macAccent ?? .systemBlue).usingColorSpace(.sRGB) ?? .systemBlue
        let red = color.redComponent > 0.5 ? color.redComponent - 0.004 : color.redComponent + 0.004
        return NSColor(srgbRed: red, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
    }

    @MainActor static func use(_ stored: String) {
        override = Theme.color(stored).map { NSColor($0) }
        if override != nil { themed = true }
    }

    private(set) static var themed = false

    @MainActor static func apply(_ stored: String, force: Bool = false) {
        guard installed, force || stored != self.stored else { return }
        self.stored = stored
        use(stored)
        guard let app = NSApp else { return }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let dark = (CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String) == "Dark"
        if let base = NSAppearance(named: dark ? .darkAqua : .aqua), base.responds(to: tintSelector),
           let tinted = base.perform(tintSelector, with: override ?? macAccent)?.takeUnretainedValue() as? NSAppearance {
            app.appearance = tinted
        }
        for window in app.windows {
            if let toolbar = window.toolbar, let selected = toolbar.selectedItemIdentifier {
                toolbar.selectedItemIdentifier = nil
                toolbar.selectedItemIdentifier = selected
            }
            window.viewsNeedDisplay = true
        }
    }
}

extension NSColor {
    @objc class var ferryControlAccentColor: NSColor { SystemAccent.answer }
}

struct FerryTheme: ViewModifier {
    @AppStorage(Theme.key) private var stored = ""

    func body(content: Content) -> some View {
        content
            .tint(Theme.tint(stored))
            .toggleStyle(ThemedToggleStyle())
            .onChange(of: stored, initial: true) { _, value in SystemAccent.apply(value) }
    }
}

struct ThemedToggleStyle: ToggleStyle {
    var checkbox = false

    func makeBody(configuration: Configuration) -> some View { ThemedToggle(configuration: configuration, checkbox: checkbox) }
}

extension ToggleStyle where Self == ThemedToggleStyle {
    static var themedCheckbox: ThemedToggleStyle { ThemedToggleStyle(checkbox: true) }
}

private struct ThemedToggle: View {
    let configuration: ToggleStyleConfiguration
    let checkbox: Bool
    @AppStorage(Theme.key) private var stored = ""

    var body: some View {
        Group {
            if checkbox { Toggle(configuration).toggleStyle(.checkbox) } else { Toggle(configuration).toggleStyle(.automatic) }
        }
        .tint(Theme.tint(stored))
        .id(stored)
    }
}

extension View {
    func ferryTheme() -> some View { modifier(FerryTheme()) }
}

struct ThemeColorSetting: View {
    @AppStorage(Theme.key) private var stored = ""

    var body: some View {
        LabeledContent("Theme color") {
            HStack(spacing: 10) {
                Button("Use Mac's Accent Color") { stored = "" }
                    .disabled(stored.isEmpty)
                    .help(stored.isEmpty ? "Ferry already uses the accent color chosen in System Settings ▸ Appearance."
                          : "Go back to the accent color chosen in System Settings ▸ Appearance")
                ColorPicker("Theme color", selection: Binding(
                    get: { Theme.tint(stored) ?? Color(nsColor: .controlAccentColor) },
                    set: { stored = Theme.encode($0) }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .help("The color of Ferry's buttons, switches, checkboxes and highlights. Click the swatch to pick any color with Apple's color picker.")
    }
}
