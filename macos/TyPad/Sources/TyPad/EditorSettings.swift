#if os(macOS)
import AppKit
typealias EditorColor = NSColor
#else
import UIKit
typealias EditorColor = UIColor
#endif
import SwiftUI

// Semantic colors from https://catppuccin.com/palette/.
enum EditorTheme: String, CaseIterable {
    case system, latte, frappe, macchiato, mocha

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .latte: return "Catppuccin Latte"
        case .frappe: return "Catppuccin Frappé"
        case .macchiato: return "Catppuccin Macchiato"
        case .mocha: return "Catppuccin Mocha"
        }
    }
    var scheme: ColorScheme? { self == .system ? nil : (self == .latte ? .light : .dark) }
    var colors: [EditorColor] {
        let hex: [UInt32]
        switch self {
        case .system:
            #if os(macOS)
            return [.textBackgroundColor, .textColor, .secondaryLabelColor, .systemPurple, .systemBlue, .systemOrange, .systemRed]
            #else
            return [.systemBackground, .label, .secondaryLabel, .systemPurple, .systemBlue, .systemOrange, .systemRed]
            #endif
        case .latte: hex = [0xeff1f5, 0x4c4f69, 0x6c6f85, 0x8839ef, 0x1e66f5, 0xfe640b, 0x40a02b]
        case .frappe: hex = [0x303446, 0xc6d0f5, 0xa5adce, 0xca9ee6, 0x8caaee, 0xef9f76, 0xa6d189]
        case .macchiato: hex = [0x24273a, 0xcad3f5, 0xa5adcb, 0xc6a0f6, 0x8aadf4, 0xf5a97f, 0xa6da95]
        case .mocha: hex = [0x1e1e2e, 0xcdd6f4, 0xa6adc8, 0xcba6f7, 0x89b4fa, 0xfab387, 0xa6e3a1]
        }
        return hex.map { EditorColor(red: CGFloat(($0 >> 16) & 255) / 255,
                                 green: CGFloat(($0 >> 8) & 255) / 255,
                                 blue: CGFloat($0 & 255) / 255, alpha: 1) }
    }
}

enum EditorAppearance: String, CaseIterable {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

struct EditorPreferences: DynamicProperty {
    @AppStorage("editorAppearance") var appearance = EditorAppearance.system
    @AppStorage("editorLightTheme") var lightTheme = EditorTheme.system
    @AppStorage("editorDarkTheme") var darkTheme = EditorTheme.system
    @Environment(\.colorScheme) private var systemScheme
    var scheme: ColorScheme { appearance.scheme ?? systemScheme }
    var theme: EditorTheme { scheme == .dark ? darkTheme : lightTheme }

    static func migrate(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: "editorAppearance") == nil else { return }
        let old = EditorTheme(rawValue: defaults.string(forKey: "editorTheme") ?? "system") ?? .system
        defaults.set(old.scheme == .light ? "light" : old.scheme == .dark ? "dark" : "system", forKey: "editorAppearance")
        defaults.set(old.scheme == .light ? old.rawValue : "system", forKey: "editorLightTheme")
        defaults.set(old.scheme == .dark ? old.rawValue : "system", forKey: "editorDarkTheme")
    }
}

struct EditorSettingsView: View {
    @AppStorage("editorFontName") private var fontName = ""
    @AppStorage("editorFontSize") private var fontSize = 14.0
    private var preferences = EditorPreferences()
    private var theme: EditorTheme { preferences.theme }
    #if os(macOS)
    private let fonts = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    #else
    private let fonts = UIFont.familyNames.sorted()
    #endif

    var body: some View {
        Form {
            Section("Source Editor") {
                Picker("Font", selection: $fontName) {
                    Text("System Monospaced").tag("")
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                    if !fontName.isEmpty && !fonts.contains(fontName) { Text(fontName).tag(fontName) }
                }
                Stepper(value: $fontSize, in: 8...40, step: 1) {
                    LabeledContent("Font Size") { Text("\(Int(fontSize)) pt").monospacedDigit() }
                }
                Picker("Appearance", selection: preferences.$appearance) {
                    ForEach(EditorAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Light Theme", selection: preferences.$lightTheme) {
                    ForEach([EditorTheme.system, .latte], id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Dark Theme", selection: preferences.$darkTheme) {
                    ForEach([EditorTheme.system, .frappe, .macchiato, .mocha], id: \.self) { Text($0.title).tag($0) }
                }
                Text("These settings affect source editing, not the exported document.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                Text("= TyPad\nHello, 世界!\n#let size = 14pt")
                    .font(Font(editorFont(name: fontName, size: fontSize)))
                    .foregroundStyle(Color(theme.colors[1]))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Color(theme.colors[0]), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 480).fixedSize(horizontal: false, vertical: true)
        #endif
        .preferredColorScheme(preferences.appearance.scheme)
    }
}

#if os(macOS)
func editorFont(name: String, size: Double) -> NSFont {
    let size = CGFloat(size.isFinite ? min(40, max(8, size)) : 14)
    return NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}

#else
func editorFont(name: String, size: Double) -> UIFont {
    let size = CGFloat(size.isFinite ? min(40, max(8, size)) : 14)
    let font = UIFont(name: name, size: size)
        ?? UIFont.fontNames(forFamilyName: name).first.flatMap { UIFont(name: $0, size: size) }
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
}
#endif
