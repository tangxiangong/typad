import AppKit
import SwiftUI

@main
struct SettingsChecks {
    static func main() {
        assert(EditorTheme.allCases.count == 5)
        assert(EditorTheme.system.scheme == nil)
        assert(EditorTheme.latte.scheme == .light)
        for theme in [EditorTheme.frappe, .macchiato, .mocha] { assert(theme.scheme == .dark) }
        for theme in EditorTheme.allCases {
            assert(theme.colors.count == 7)
            assert(EditorTheme(rawValue: theme.rawValue) == theme)
        }
        assert(editorFont(name: "missing-font-typad", size: 14).pointSize == 14)
        assert(editorFont(name: "", size: -10).pointSize == 8)
        assert(editorFont(name: "", size: 100).pointSize == 40)
        assert(editorFont(name: "", size: .nan).pointSize == 14)
        for old in EditorTheme.allCases {
            let suite = "TyPad.SettingsChecks." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(old.rawValue, forKey: "editorTheme")
            EditorPreferences.migrate(defaults: defaults)
            assert(defaults.string(forKey: "editorAppearance") == (old.scheme == .light ? "light" : old.scheme == .dark ? "dark" : "system"))
            assert(defaults.string(forKey: "editorLightTheme") == (old.scheme == .light ? old.rawValue : "system"))
            assert(defaults.string(forKey: "editorDarkTheme") == (old.scheme == .dark ? old.rawValue : "system"))
            defaults.set("frappe", forKey: "editorDarkTheme")
            EditorPreferences.migrate(defaults: defaults)
            assert(defaults.string(forKey: "editorDarkTheme") == "frappe")
        }
        assert(EditorAppearance.system.scheme == nil)
        assert(EditorAppearance.light.scheme == .light)
        assert(EditorAppearance.dark.scheme == .dark)
        print("Settings checks passed: theme variants, color schemes, font fallback and size bounds")
    }
}
